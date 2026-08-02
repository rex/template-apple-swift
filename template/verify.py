#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
"""verify.py — the structural gate for this template and everything it generates.

Two modes, chosen by the tree itself:

* **template mode** — no `docs/onboarding-answers.yaml`. The tree is the
  committed superset: every component enabled, identity still `MyApp` /
  `com.example.myapp`. Runs the structural checks only.
* **generated mode** — `docs/onboarding-answers.yaml` is present. Reads the
  archived answers for the identity and component set, then runs the structural
  checks PLUS the post-generation assertions (no orphan markers, no references
  to pruned symbols, include list matches, bundle IDs explicit and nested,
  zero residual tokens).

The component registry is read from `<root>/template/components.yaml` when it
exists and otherwise from the copy next to this script — a generated repo has
self-destructed `template/`, so verify has to bring its own.

Usage: verify.py [--root DIR] [--manifest FILE] [--quiet]
Exit codes: 0 clean / 1 violations found / 2 cannot run.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tmpl import checks_generated, checks_structure  # noqa: E402
from tmpl import manifest as manifest_mod  # noqa: E402
from tmpl.answers import DEFAULT_IDENT, Ident  # noqa: E402
from tmpl.context import ONBOARDING_ANSWERS, GenerateError  # noqa: E402


def load_archive(root: Path):
    """(Ident, enabled) from the archived answers, or None in template mode."""
    import yaml

    path = root / ONBOARDING_ANSWERS
    if not path.is_file():
        return None
    doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    ident_doc = doc.get("identity") or {}
    ident = Ident(
        app_name=ident_doc.get("app_name", DEFAULT_IDENT["app_name"]),
        display_name=ident_doc.get("display_name", ident_doc.get("app_name", "")),
        bundle_root=ident_doc.get("bundle_root", DEFAULT_IDENT["bundle_root"]),
        team_id=ident_doc.get("team_id", DEFAULT_IDENT["team_id"]),
        slug=ident_doc.get("slug", ident_doc.get("app_name", "").lower()),
    )
    enabled = {cid for cid, on in (doc.get("components") or {}).items() if on}
    return ident, enabled


def template_identity() -> Ident:
    return Ident(
        app_name=DEFAULT_IDENT["app_name"],
        display_name=DEFAULT_IDENT["app_name"],
        bundle_root=DEFAULT_IDENT["bundle_root"],
        team_id=DEFAULT_IDENT["team_id"],
        slug=DEFAULT_IDENT["app_name"].lower(),
    )


def resolve_manifest(root: Path, override: Path | None) -> Path:
    for candidate in (override, root / "template" / "components.yaml", HERE / "components.yaml"):
        if candidate and candidate.is_file():
            return candidate
    raise GenerateError("no components.yaml found (pass --manifest)")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Structural gate for template-apple-swift.")
    parser.add_argument("--root", type=Path, default=HERE.parent, help="tree to check")
    parser.add_argument("--manifest", type=Path, default=None, help="components.yaml override")
    parser.add_argument("--quiet", action="store_true", help="print only the verdict")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    if not root.is_dir():
        print(f"verify: no such directory: {root}", file=sys.stderr)
        return 2
    try:
        registry = manifest_mod.load(resolve_manifest(root, args.manifest))
    except GenerateError as exc:
        print(f"verify: {exc}", file=sys.stderr)
        return 2

    archive = load_archive(root)
    if archive is None:
        ident, enabled, mode = template_identity(), set(registry.component_ids), "template"
        result = checks_structure.run(root, registry, ident, enabled)
        for err in manifest_mod.validate_against_tree(registry, root):
            result.fail(f"components.yaml: {err}")
    else:
        ident, enabled = archive
        mode = "generated"
        result = checks_structure.run(root, registry, ident, enabled)
        result.extend(checks_generated.run(root, registry, ident, enabled))

    if not args.quiet:
        print(f"verify: {mode} mode · root={root} · components enabled: {len(enabled)}")
        for warn in result.warns:
            print(f"  warn: {warn}")
    for fail in result.fails:
        print(f"  FAIL: {fail}")
    print(f"verify: {len(result.fails)} failure(s), {len(result.warns)} warning(s)")
    return 1 if result.fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
