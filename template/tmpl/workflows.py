"""GitHub Actions surgery for the generated repo.

Two edits, both defined by whole-line markers or an explicitly named matrix
key so neither depends on W2C's formatting:

* `ci.yml` carries jobs that only make sense while this repo IS the template
  (generating every combo and diffing it). They sit between whole-line
  `# >>> template-ci` / `# <<< template-ci` markers and are removed wholesale.
* `verify-macos.yml` fans out across the six `template/ci-combos/*.yaml`
  configurations. A generated repo has exactly one configuration, so the
  matrix collapses to it.

Both are best-effort by design: `ops.ci_system` may be `xcode_cloud` or
`none`, in which case the workflows may not exist at all. A missing file is a
note, never an error.
"""

from __future__ import annotations

import re

from .context import (
    CI_WORKFLOW,
    RELEASE_DEST,
    RELEASE_PAYLOAD,
    VERIFY_MACOS_WORKFLOW,
    Ctx,
)

BEGIN = "# >>> template-ci"
END = "# <<< template-ci"
MATRIX_KEY_RE = re.compile(r"^(\s*)(combo|config|configuration):\s*(\[.*\]|)\s*$")


def run(ctx: Ctx) -> None:
    _copy_release(ctx)
    _strip_template_jobs(ctx)
    _collapse_matrix(ctx)


def _copy_release(ctx: Ctx) -> None:
    if (ctx.answers.get("ops") or {}).get("ci_system") != "github_actions":
        ctx.plan.note("ops.ci_system is not github_actions — release.yml not installed")
        return
    payload = ctx.root / RELEASE_PAYLOAD
    if not payload.is_file():
        ctx.plan.note(f"{RELEASE_PAYLOAD} absent — release workflow not installed")
        return
    ctx.write(ctx.root / RELEASE_DEST, payload.read_text(encoding="utf-8"), added=True)


def strip_marked_blocks(text: str) -> tuple[str, int]:
    """Remove every `# >>> template-ci` … `# <<< template-ci` block. Pure."""
    out: list[str] = []
    removed, skipping = 0, False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped == BEGIN:
            skipping = True
            removed += 1
            continue
        if stripped == END:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    return "".join(out), removed


def _strip_template_jobs(ctx: Ctx) -> None:
    path = ctx.root / CI_WORKFLOW
    if not path.is_file():
        ctx.plan.note(f"{CI_WORKFLOW} absent — no template-only jobs to strip")
        return
    text = path.read_text(encoding="utf-8")
    new_text, removed = strip_marked_blocks(text)
    if removed:
        ctx.plan.note(f"{CI_WORKFLOW}: removed {removed} template-only job block(s)")
        ctx.write(path, new_text)


def collapse_matrix(text: str, combo: str) -> tuple[str, bool]:
    """Reduce a combo matrix list to the single generated configuration. Pure."""
    lines = text.splitlines(keepends=True)
    for i, raw in enumerate(lines):
        match = MATRIX_KEY_RE.match(raw.rstrip("\n"))
        if match is None:
            continue
        indent, key, flow = match.groups()
        if flow:
            lines[i] = f"{indent}{key}: [{combo}]\n"
            return "".join(lines), True
        end = i + 1
        while end < len(lines) and lines[end].lstrip().startswith("- "):
            end += 1
        if end > i + 1:
            lines[i + 1 : end] = [f"{indent}  - {combo}\n"]
            return "".join(lines), True
    return text, False


def _collapse_matrix(ctx: Ctx) -> None:
    path = ctx.root / VERIFY_MACOS_WORKFLOW
    if not path.is_file():
        ctx.plan.note(f"{VERIFY_MACOS_WORKFLOW} absent — matrix not collapsed")
        return
    text = path.read_text(encoding="utf-8")
    new_text, done = collapse_matrix(text, ctx.ident.slug)
    if done:
        ctx.plan.note(f"{VERIFY_MACOS_WORKFLOW}: matrix collapsed to '{ctx.ident.slug}'")
        ctx.write(path, new_text)
    else:
        ctx.plan.note(f"{VERIFY_MACOS_WORKFLOW}: no combo matrix key found — left as-is")
