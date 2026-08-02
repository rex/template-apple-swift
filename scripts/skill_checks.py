#!/usr/bin/env python3
"""skill_checks.py — check implementations for verify_skill.py.

Each check_* function runs one structural check against a skill
directory and records pass/fail on a shared Result. verify_skill.py
imports and orchestrates them — run that, not this file.
"""

from __future__ import annotations

import json
import os
import py_compile
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml


# ─── ANSI helpers ───────────────────────────────────────────────────────

_TTY = sys.stdout.isatty() and "NO_COLOR" not in os.environ
_R = "\033[31m" if _TTY else ""
_G = "\033[32m" if _TTY else ""
_Y = "\033[33m" if _TTY else ""
_B = "\033[34m" if _TTY else ""
_D = "\033[2m" if _TTY else ""
_X = "\033[0m" if _TTY else ""


@dataclass
class Result:
    passed: int = 0
    failed: int = 0
    fail_details: list[str] = field(default_factory=list)

    def pass_(self, msg: str) -> None:
        print(f"  {_G}✓{_X} {msg}")
        self.passed += 1

    def fail(self, msg: str) -> None:
        print(f"  {_R}✗{_X} {msg}")
        self.failed += 1
        self.fail_details.append(msg)


def section(title: str) -> None:
    print(f"\n{_B}{title}{_X}")


# ─── Check implementations ─────────────────────────────────────────────

def check_frontmatter(skill_dir: Path, r: Result) -> None:
    section("1. SKILL.md frontmatter")
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        r.fail("SKILL.md missing at skill root")
        return
    text = skill_md.read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        r.fail("no frontmatter found (expected --- ... --- block at top)")
        return
    try:
        fm = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        r.fail(f"frontmatter YAML invalid: {e}")
        return
    if not isinstance(fm, dict) or not fm.get("name"):
        r.fail("frontmatter missing `name:` field")
        return
    r.pass_("SKILL.md frontmatter valid")

    body_lines = sum(1 for _ in re.finditer(r"^.+$", text[m.end():], re.MULTILINE))
    if body_lines < 5:
        r.fail(f"SKILL.md body appears empty or near-empty ({body_lines} lines after frontmatter)")
    else:
        r.pass_(f"SKILL.md body is non-empty ({body_lines} lines)")


def check_links(skill_dir: Path, r: Result) -> None:
    section("2. Relative links in SKILL.md resolve")
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return
    text = skill_md.read_text()
    broken = 0
    for m in re.finditer(r"\]\(([^)]+)\)", text):
        link = m.group(1)
        # Skip URLs and bare anchors
        if link.startswith(("http://", "https://", "mailto:", "#")):
            continue
        # Strip anchor
        path = link.split("#", 1)[0]
        if not path:
            continue
        if not (skill_dir / path).exists():
            r.fail(f"broken link: {link} → {path}")
            broken += 1
    if broken == 0:
        r.pass_("all relative links resolve")


def check_executable_bits(skill_dir: Path, r: Result) -> None:
    section("3. Shell script executable bits")
    needs = 0
    sh_files = sorted(skill_dir.rglob("*.sh"))
    for sh in sh_files:
        if not os.access(sh, os.X_OK):
            r.fail(f"not executable: {sh.relative_to(skill_dir)}")
            needs += 1
    if needs == 0:
        r.pass_(f"all {len(sh_files)} shell scripts have executable bit set")


def check_bash_syntax(skill_dir: Path, r: Result) -> None:
    section("4. Shell script syntax (bash -n)")
    syntax_fail = 0
    sh_files = sorted(skill_dir.rglob("*.sh"))
    for sh in sh_files:
        result = subprocess.run(
            ["bash", "-n", str(sh)],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            r.fail(f"syntax error in {sh.relative_to(skill_dir)}: "
                   f"{result.stderr.strip().splitlines()[0] if result.stderr else 'unknown'}")
            syntax_fail += 1
    if syntax_fail == 0:
        r.pass_(f"all {len(sh_files)} shell scripts pass bash -n")


def check_python_syntax(skill_dir: Path, r: Result) -> None:
    section("5. Python script syntax (py_compile)")
    fail_count = 0
    # Skip __pycache__ AND template placeholders (files named _template.py
    # contain <angle-bracket> placeholders by design and are not valid
    # Python until rendered).
    py_files = sorted(
        p for p in skill_dir.rglob("*.py")
        if "__pycache__" not in p.parts and not p.name.endswith("_template.py")
    )
    for py in py_files:
        try:
            py_compile.compile(str(py), doraise=True)
        except py_compile.PyCompileError as e:
            r.fail(f"syntax error in {py.relative_to(skill_dir)}: {e.msg.splitlines()[0]}")
            fail_count += 1
    if fail_count == 0 and py_files:
        r.pass_(f"all {len(py_files)} Python scripts compile")
    elif not py_files:
        r.pass_("no Python scripts to check")


def check_json(skill_dir: Path, r: Result) -> None:
    section("6. JSON files parse")
    fail_count = 0
    json_files = sorted(
        p for p in skill_dir.rglob("*.json")
        if "node_modules" not in p.parts and "__pycache__" not in p.parts
    )
    for j in json_files:
        try:
            with j.open() as f:
                json.load(f)
        except json.JSONDecodeError as e:
            r.fail(f"JSON parse error in {j.relative_to(skill_dir)}: {e}")
            fail_count += 1
    if fail_count == 0:
        r.pass_(f"all {len(json_files)} JSON files parse")


def check_yaml(skill_dir: Path, r: Result) -> None:
    section("7. YAML files parse")
    fail_count = 0
    yaml_files = sorted(
        p for ext in ("*.yml", "*.yaml") for p in skill_dir.rglob(ext)
    )
    for y in yaml_files:
        try:
            with y.open() as f:
                list(yaml.safe_load_all(f))
        except yaml.YAMLError as e:
            r.fail(f"YAML parse error in {y.relative_to(skill_dir)}: {str(e).splitlines()[0]}")
            fail_count += 1
    if fail_count == 0:
        r.pass_(f"all {len(yaml_files)} YAML files parse")


SECRET_PATTERNS = [
    re.compile(r"ghp_[A-Za-z0-9]{36,}"),
    re.compile(r"gho_[A-Za-z0-9]{36,}"),
    re.compile(r"sk-[a-zA-Z0-9]{40,}"),
    re.compile(r"sk-ant-[a-zA-Z0-9_-]{40,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    re.compile(r"xox[bap]-[0-9]{10,}-[0-9]{10,}-[a-zA-Z0-9]{24,}"),
]


def check_secrets(skill_dir: Path, r: Result) -> None:
    section("8. No secret-like strings")
    hits = 0
    self_path = Path(__file__).resolve()
    for path in skill_dir.rglob("*"):
        if not path.is_file():
            continue
        if any(part in (".git", "node_modules", "__pycache__") for part in path.parts):
            continue
        if path.resolve() == self_path:
            continue  # skip this script's own pattern definitions
        try:
            text = path.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            for pat in SECRET_PATTERNS:
                if pat.search(line):
                    r.fail(
                        f"possible secret: {path.relative_to(skill_dir)}:{line_no}: "
                        f"{line[:80]}"
                    )
                    hits += 1
    if hits == 0:
        r.pass_("no secret patterns matched")


DESTRUCTIVE_PATTERNS = [
    re.compile(r"terraform\s+apply\s+.*-auto-approve"),
    re.compile(r"terraform\s+destroy"),
    re.compile(r"terraform\s+force-unlock"),
    re.compile(r"terraform\s+state\s+rm"),
    re.compile(r"terraform\s+state\s+push"),
    re.compile(r"rm\s+-rf\s+/"),
]

SAFETY_CTX_RE = re.compile(
    r"(forbid|denied|never|not allowed|block|refuse|must not|disallow)",
    re.IGNORECASE,
)
TEST_CTX_RE = re.compile(
    r"(bash-guard|test[- ]the[- ]guard|must[- ]work|guard\.sh|blocked by|"
    r"expected: exit 2|tool_input)",
    re.IGNORECASE,
)
INLINE_CODE_RE = re.compile(
    r"`[^`]*(terraform destroy|terraform apply|rm -rf|force-unlock|state rm|"
    r"state push)[^`]*`"
)


def check_destructive_commands(skill_dir: Path, r: Result) -> None:
    section("9. No destructive terraform commands in docs/examples")
    hits = 0
    for doc in sorted(
        p for ext in ("README.md", "CHECKLIST.md")
        for p in skill_dir.rglob(ext)
    ):
        # Skip the scripts/ subdirectory — deny lists there are intentional
        if "scripts" in doc.parts:
            continue
        lines = doc.read_text().splitlines()
        for ln, content in enumerate(lines, 1):
            for pat in DESTRUCTIVE_PATTERNS:
                if not pat.search(content):
                    continue
                # Surrounding context: ±5 lines flattened to one string
                ctx_start = max(0, ln - 6)
                ctx_end = min(len(lines), ln + 3)
                context = " ".join(lines[ctx_start:ctx_end])
                if SAFETY_CTX_RE.search(context):
                    continue
                if TEST_CTX_RE.search(context):
                    continue
                if INLINE_CODE_RE.search(content):
                    continue
                r.fail(
                    f"destructive command in {doc.relative_to(skill_dir)}:{ln} → "
                    f"{content[:80]}..."
                )
                hits += 1
    if hits == 0:
        r.pass_("no destructive commands appear outside deny/forbid context")


def check_skill_md_refs(skill_dir: Path, r: Result) -> None:
    section("10. Scripts/Templates/References paths in SKILL.md resolve")
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return
    text = skill_md.read_text()
    # Pull body of "## Scripts", "## Templates", "## References" sections
    sections = re.findall(
        r"^## (?:Scripts|Templates|References)\b.*?(?=^## |\Z)",
        text, re.MULTILINE | re.DOTALL,
    )
    broken = 0
    for body in sections:
        # backticked path tokens that look like file paths
        for m in re.finditer(r"`([^` \n]+/[^` \n]+\.[a-zA-Z0-9]+)`", body):
            ref = m.group(1)
            if ref.startswith(("http://", "https://", "mailto:", "#")):
                continue
            if not (skill_dir / ref).exists():
                r.fail(f"referenced path missing: {ref}")
                broken += 1
    if broken == 0:
        r.pass_("all Scripts/Templates/References paths in SKILL.md resolve")


def check_composable_fragments(skill_dir: Path, r: Result) -> None:
    section("11. Composable skills with vibe_yaml_namespaces ship a fragment")
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return
    text = skill_md.read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        r.pass_("no frontmatter — N/A")
        return
    fm = yaml.safe_load(m.group(1)) or {}
    namespaces = fm.get("vibe_yaml_namespaces") or []
    if not namespaces:
        r.pass_("skill declares no vibe_yaml_namespaces — N/A")
        return
    fragment_path = skill_dir / "vibe-schema-fragment.yaml"
    if not fragment_path.is_file():
        r.fail(
            f"declares vibe_yaml_namespaces {namespaces} but no "
            f"vibe-schema-fragment.yaml at {fragment_path.relative_to(skill_dir)}"
        )
        return
    try:
        fragment = yaml.safe_load(fragment_path.read_text()) or {}
    except yaml.YAMLError as e:
        r.fail(f"vibe-schema-fragment.yaml parse error: {e}")
        return
    missing = [ns for ns in namespaces if ns not in fragment]
    if missing:
        r.fail(
            f"vibe-schema-fragment.yaml missing top-level keys for declared "
            f"namespaces: {missing}"
        )
        return
    r.pass_(f"fragment present and covers all {len(namespaces)} declared namespace(s)")


def check_makefile_scripts(skill_dir: Path, r: Result) -> None:
    section("12. Makefile-referenced scripts exist")
    makefile = skill_dir / "templates" / "standard" / "Makefile"
    if not makefile.is_file():
        r.pass_("skill ships no standard Makefile — N/A")
        return
    refs = sorted(set(re.findall(r"scripts/([A-Za-z0-9_.-]+\.py)",
                                 makefile.read_text())))
    if not refs:
        r.pass_("standard Makefile invokes no scripts/ files — N/A")
        return
    missing = [ref for ref in refs
               if not (skill_dir / "scripts" / ref).is_file()]
    if missing:
        for ref in missing:
            r.fail(f"Makefile calls scripts/{ref} but {skill_dir.name}/"
                   f"scripts/{ref} does not exist")
        return
    r.pass_(f"all {len(refs)} Makefile-referenced script(s) exist in scripts/")


def check_hook_parity(skill_dir: Path, r: Result) -> None:
    section("13. Greenfield / brownfield hook parity")
    gf = skill_dir / "templates" / "greenfield" / ".claude" / "hooks"
    bf = (skill_dir / "templates" / "brownfield" / "PR5-delegation-hooks"
          / "files" / ".claude" / "hooks")
    if not (gf.is_dir() and bf.is_dir()):
        r.pass_("skill ships no greenfield+brownfield hook pair — N/A")
        return
    gf_hooks = {p.name: p for p in gf.glob("*.sh")}
    bf_hooks = {p.name: p for p in bf.glob("*.sh")}
    diverged = 0
    for name in sorted(set(gf_hooks) | set(bf_hooks)):
        if name not in gf_hooks:
            r.fail(f"hook {name}: in brownfield but missing from greenfield")
            diverged += 1
        elif name not in bf_hooks:
            r.fail(f"hook {name}: in greenfield but missing from brownfield")
            diverged += 1
        elif gf_hooks[name].read_bytes() != bf_hooks[name].read_bytes():
            r.fail(f"hook {name}: greenfield and brownfield copies differ "
                   "(one is stale — sync them)")
            diverged += 1
    if diverged == 0:
        r.pass_(f"all {len(gf_hooks)} hook(s) identical across "
                "greenfield + brownfield")
