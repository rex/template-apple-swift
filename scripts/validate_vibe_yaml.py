#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
"""validate_vibe_yaml.py — validate a repo's VIBE.yaml.

Loads agentic-skeleton's root schema, discovers installed composable
skills via their `vibe_yaml_namespaces` SKILL.md frontmatter, merges each
skill's `vibe-schema-fragment.yaml` under its declared namespace, sets
`additionalProperties: false` on the merged result, then invokes
`check-jsonschema` to validate the repo's VIBE.yaml against it.

Hard requires `check-jsonschema` on PATH (no fallbacks). Install with:
    brew install check-jsonschema
    # or
    uv tool install check-jsonschema
    # or
    pip install check-jsonschema

Usage:
    validate_vibe_yaml.py [--vibe-yaml PATH] [--skills-dir DIR]
                         [--skill-search-paths P1:P2:...]
                         [--show-merged-schema] [--quiet]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml  # PyYAML — required


# ─── ANSI helpers ───────────────────────────────────────────────────────

_TTY = sys.stderr.isatty() and "NO_COLOR" not in os.environ
_R = "\033[31m" if _TTY else ""
_G = "\033[32m" if _TTY else ""
_Y = "\033[33m" if _TTY else ""
_X = "\033[0m" if _TTY else ""


def fail(msg: str, code: int = 1) -> None:
    print(f"{_R}✗{_X} {msg}", file=sys.stderr)
    sys.exit(code)


def ok(msg: str) -> None:
    print(f"{_G}✓{_X} {msg}", file=sys.stderr)


def warn(msg: str) -> None:
    print(f"{_Y}!{_X} {msg}", file=sys.stderr)


# ─── Schema discovery + merge ──────────────────────────────────────────

def require_check_jsonschema() -> None:
    if shutil.which("check-jsonschema") is None:
        fail(
            "check-jsonschema not found on PATH.\n"
            "  install: brew install check-jsonschema\n"
            "        or uv tool install check-jsonschema\n"
            "        or pip install check-jsonschema",
            code=2,
        )


def parse_frontmatter(skill_md: Path) -> dict[str, Any] | None:
    text = skill_md.read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return None
    parsed = yaml.safe_load(m.group(1))
    return parsed if isinstance(parsed, dict) else None


def load_skeleton_schema(skeleton_dir: Path) -> dict[str, Any]:
    schema_doc_path = skeleton_dir / "references" / "vibe-yaml-schema.md"
    if not schema_doc_path.is_file():
        fail(f"agentic-skeleton schema doc missing: {schema_doc_path}")
    text = schema_doc_path.read_text()
    m = re.search(r"```yaml\n(\$schema:.*?)\n```", text, re.DOTALL)
    if not m:
        fail(f"no parseable schema block in {schema_doc_path}")
    schema = yaml.safe_load(m.group(1))
    if not isinstance(schema, dict) or "properties" not in schema:
        fail(f"schema in {schema_doc_path} has no `properties:` block")
    return schema


def discover_fragments(
    search_paths: list[str],
) -> list[tuple[str, dict[str, Any], str]]:
    """Return [(namespace, sub_schema, skill_name), ...] across installed skills."""
    fragments: list[tuple[str, dict[str, Any], str]] = []
    seen: dict[str, str] = {}

    for raw in search_paths:
        root = Path(raw).expanduser()
        if not root.is_dir():
            continue
        for skill_md in sorted(root.glob("*/SKILL.md")):
            fm = parse_frontmatter(skill_md)
            if not fm:
                continue
            namespaces = fm.get("vibe_yaml_namespaces") or []
            if not namespaces:
                continue
            if not isinstance(namespaces, list):
                fail(
                    f"{skill_md}: vibe_yaml_namespaces must be a list, "
                    f"got {type(namespaces).__name__}"
                )
            skill_dir = skill_md.parent
            skill_name = fm.get("name") or skill_dir.name
            fragment_path = skill_dir / "vibe-schema-fragment.yaml"
            if not fragment_path.is_file():
                fail(
                    f"skill '{skill_name}' declares vibe_yaml_namespaces "
                    f"{namespaces} but ships no vibe-schema-fragment.yaml "
                    f"(expected at {fragment_path})"
                )
            fragment = yaml.safe_load(fragment_path.read_text()) or {}
            if not isinstance(fragment, dict):
                fail(f"{fragment_path}: top-level must be a mapping")

            for ns in namespaces:
                if ns in seen:
                    if seen[ns] == skill_name:
                        continue  # same skill in multiple search paths — skip
                    fail(
                        f"namespace conflict: '{ns}' declared by both "
                        f"'{seen[ns]}' and '{skill_name}'"
                    )
                if ns not in fragment:
                    fail(
                        f"skill '{skill_name}' declares namespace '{ns}' "
                        f"but its fragment has no top-level '{ns}:' key"
                    )
                seen[ns] = skill_name
                fragments.append((ns, fragment[ns], skill_name))
    return fragments


def merge_schema(
    skeleton: dict[str, Any],
    fragments: list[tuple[str, dict[str, Any], str]],
) -> dict[str, Any]:
    merged = json.loads(json.dumps(skeleton))  # deep copy via JSON round-trip
    for ns, sub_schema, _skill in fragments:
        merged["properties"][ns] = sub_schema
    return merged


# ─── Validation ────────────────────────────────────────────────────────

def run_check_jsonschema(schema: dict[str, Any], vibe_yaml: Path) -> int:
    fd, tmp_path = tempfile.mkstemp(suffix=".schema.json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(schema, f, indent=2)
        result = subprocess.run(
            ["check-jsonschema", "--schemafile", tmp_path, str(vibe_yaml)],
            check=False,
        )
        return result.returncode
    finally:
        os.unlink(tmp_path)


# ─── Entry point ───────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a repo's VIBE.yaml against the merged "
        "agentic-skeleton + composable-skill schema.",
    )
    parser.add_argument(
        "--vibe-yaml", default="VIBE.yaml",
        help="path to the VIBE.yaml to validate (default: ./VIBE.yaml)",
    )
    parser.add_argument(
        "--skills-dir",
        help="path to agentic-skeleton skill (default: derived from this "
             "script's location)",
    )
    parser.add_argument(
        "--skill-search-paths",
        default="~/.claude/skills:~/.codex/skills",
        help="colon-separated paths searched for installed sibling skills",
    )
    parser.add_argument(
        "--show-merged-schema", action="store_true",
        help="print the merged JSON Schema to stdout and exit (no validation)",
    )
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if args.skills_dir:
        skeleton_dir = Path(args.skills_dir).resolve()
    else:
        skeleton_dir = Path(__file__).resolve().parent.parent
    if not (skeleton_dir / "SKILL.md").is_file():
        fail(f"agentic-skeleton not found at {skeleton_dir} (no SKILL.md)")

    vibe_yaml = Path(args.vibe_yaml).resolve()
    if not vibe_yaml.is_file():
        fail(f"VIBE.yaml not found: {vibe_yaml}")

    if not args.quiet:
        ok(f"agentic-skeleton: {skeleton_dir}")
        ok(f"VIBE.yaml: {vibe_yaml}")

    skeleton_schema = load_skeleton_schema(skeleton_dir)
    if not args.quiet:
        n = len(skeleton_schema["properties"])
        ok(f"loaded skeleton schema ({n} skeleton-owned top-level keys)")

    search_paths = [p for p in args.skill_search_paths.split(":") if p]
    fragments = discover_fragments(search_paths)
    if not args.quiet:
        if fragments:
            ns_list = ", ".join(f"{ns} (from {skill})" for ns, _, skill in fragments)
            ok(f"discovered {len(fragments)} composable namespace(s): {ns_list}")
        else:
            ok("no composable-skill fragments installed (skeleton-only)")

    merged = merge_schema(skeleton_schema, fragments)

    if args.show_merged_schema:
        json.dump(merged, sys.stdout, indent=2)
        print()
        return 0

    require_check_jsonschema()
    rc = run_check_jsonschema(merged, vibe_yaml)
    if rc == 0 and not args.quiet:
        ok("VIBE.yaml passes schema validation")
    return rc


if __name__ == "__main__":
    sys.exit(main())
