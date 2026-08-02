"""Shared generator state: the error type, the recorded plan, and Ctx.

`Plan` is the audit trail every stage appends to. `--dry-run` prints it
instead of writing; the combo tests compare it against an independently
predicted file set (`predict.py`), so a stage that lies about what it did
fails the matrix.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class GenerateError(RuntimeError):
    """Fatal, actionable generator error. Always carries the fix."""


# --- paths the pipeline and the file-set oracle must agree on -------------

TEMPLATE_DIR = "template"
RELEASE_PAYLOAD = "template/payload/release.yml"
RELEASE_DEST = ".github/workflows/release.yml"
CI_WORKFLOW = ".github/workflows/ci.yml"
VERIFY_MACOS_WORKFLOW = ".github/workflows/verify-macos.yml"
ONBOARDING_RECORD = "docs/onboarding-record.md"
ONBOARDING_ANSWERS = "docs/onboarding-answers.yaml"
SHARED_XCCONFIG = "Config/Shared.xcconfig"
VIBE_FILE = "VIBE.yaml"
SETTINGS_JSON = ".claude/settings.json"
SPINNER_SCRIPT = "scripts/sync_spinner_verbs.py"
SPINNER_CORPUS = (".claude/spinner-verbs.txt", ".claude/spinner-tips.txt")
STATUSLINE_SCRIPT = ".claude/statusline.sh"

GENERATED_DOCS = ("AGENTS.md", "MAP.md", "README.md", "TASK_STATE.md", "PROGRESS.md")
AGENTS_MIRRORS = ("CLAUDE.md", "GEMINI.md")

# Generated-doc line budgets (agentic-skeleton: AGENTS.md ≤150, PROGRESS ≤50).
DOC_BUDGETS = {
    "AGENTS.md": 150,
    "MAP.md": 150,
    "README.md": 130,
    "TASK_STATE.md": 120,
    "PROGRESS.md": 50,
}


@dataclass
class Plan:
    """Everything a run did (or would do), in execution order."""

    deleted: list[str] = field(default_factory=list)
    renamed: list[tuple[str, str]] = field(default_factory=list)
    rewritten: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)
    includes_removed: list[str] = field(default_factory=list)
    markers_stripped: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def note(self, msg: str) -> None:
        self.notes.append(msg)

    @property
    def destructive_count(self) -> int:
        return len(self.deleted) + len(self.includes_removed) + len(self.markers_stripped)

    def render(self) -> str:
        out: list[str] = []

        def block(title: str, items: list[str]) -> None:
            out.append(f"\n{title} ({len(items)})")
            if items:
                out.extend(f"  {i}" for i in items)
            else:
                out.append("  (none)")

        block("DELETE files", self.deleted)
        block("REMOVE include entries", self.includes_removed)
        block("STRIP marker blocks", self.markers_stripped)
        block("RENAME paths", [f"{a} -> {b}" for a, b in self.renamed])
        block("REWRITE contents", self.rewritten)
        block("ADD files", self.added)
        block("NOTES", self.notes)
        return "\n".join(out)


@dataclass
class Ctx:
    """One generation run against one tree."""

    root: Path
    """Tree being transformed (the copy under --dest, or the repo for --apply)."""

    source: Path
    """Template repo the generator itself was invoked from."""

    ident: Any
    """answers.Ident — normalized identity tokens."""

    answers: dict[str, Any]
    """Validated, defaults-filled answers document."""

    manifest: Any
    """manifest.Manifest — the parsed component registry."""

    dry_run: bool = False
    plan: Plan = field(default_factory=Plan)

    # ---- guarded filesystem mutators -------------------------------------

    def rel(self, path: Path) -> str:
        return str(path.relative_to(self.root))

    def write(self, path: Path, text: str, *, added: bool = False) -> None:
        rel = self.rel(path)
        (self.plan.added if added else self.plan.rewritten).append(rel)
        if self.dry_run:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def delete(self, path: Path) -> None:
        import shutil

        if not path.exists() and not path.is_symlink():
            return
        if path.is_dir():
            for sub in sorted(p for p in path.rglob("*") if p.is_file()):
                self.plan.deleted.append(self.rel(sub))
            if not self.dry_run:
                shutil.rmtree(path)
        else:
            self.plan.deleted.append(self.rel(path))
            if not self.dry_run:
                path.unlink()

    def move(self, src: Path, dst: Path) -> None:
        self.plan.renamed.append((self.rel(src), self.rel(dst)))
        if self.dry_run:
            return
        dst.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dst)
