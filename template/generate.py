#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6.0"]
# ///
"""generate.py — turn this template into one specific app. Runs exactly once.

    uv run template/generate.py --answers <file> [--dest DIR | --apply] [--dry-run]

    --dest DIR   copy the git-visible tree to DIR, then transform the copy.
                 The template repo is left untouched. Use this to try answers
                 on for size, and it is what the combo matrix in CI does.
    --apply      transform this repo in place. Destructive and irreversible:
                 `template/` self-destructs at the end, so there is no second
                 run. Must be typed explicitly — there is no default mode.
    --dry-run    print the full plan (deletions, include entries, marker blocks,
                 renames, writes) and exit without touching anything.

The generator runs NO git commands. `--apply` on a dirty tree is your call to
make; `git status` before you type it is the whole safety mechanism.

Refuses to run when `template/` is absent: that means this repo was already
generated, and a second pass would prune components whose files are long gone.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tmpl import answers as answers_mod  # noqa: E402
from tmpl import checks_generated, checks_structure, fsutil, gitops  # noqa: E402
from tmpl import manifest as manifest_mod  # noqa: E402
from tmpl import predict  # noqa: E402
from tmpl.context import TEMPLATE_DIR, Ctx, GenerateError  # noqa: E402

SOURCE = HERE.parent
SCHEMA = HERE / "answers.schema.json"
REGISTRY = HERE / "components.yaml"


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="generate.py",
        description="One-shot onboarding transform for template-apple-swift.",
    )
    parser.add_argument("--answers", type=Path, required=True, help="answers YAML file")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dest", type=Path, help="copy the tree here, then transform the copy")
    mode.add_argument("--apply", action="store_true", help="transform this repo in place")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, write nothing")
    args = parser.parse_args(argv)
    if not args.dry_run and not args.dest and not args.apply:
        parser.error("choose a mode: --dest DIR (safe) or --apply (in place). Add --dry-run to preview.")
    return args


def prepare(args: argparse.Namespace) -> tuple[Path, bool]:
    """Resolve the tree to transform. Returns (root, copied)."""
    if not (SOURCE / TEMPLATE_DIR).is_dir():
        raise GenerateError(
            f"{TEMPLATE_DIR}/ is absent — this repo has already been generated. "
            "The generator is one-shot by design; start from a fresh clone of the template."
        )
    if not args.dest:
        return SOURCE, False
    dest = args.dest.resolve()
    if dest == SOURCE:
        raise GenerateError("--dest must differ from the template repo; use --apply for in place")
    if dest.exists() and any(dest.iterdir()):
        raise GenerateError(f"--dest {dest} exists and is not empty")
    if args.dry_run:
        return SOURCE, False
    fsutil.copy_repo(SOURCE, dest)
    return dest, True


def build_context(args: argparse.Namespace, root: Path) -> Ctx:
    registry = manifest_mod.load(REGISTRY)
    errs = manifest_mod.validate_against_tree(registry, SOURCE)
    if errs:
        raise GenerateError(
            f"{len(errs)} component-registry violation(s) — the registry has drifted "
            f"from the tree:\n  " + "\n  ".join(errs)
        )
    doc, ident, warns = answers_mod.load(args.answers.resolve(), SCHEMA, registry)
    ctx = Ctx(
        root=root,
        source=SOURCE,
        ident=ident,
        answers=doc,
        manifest=registry,
        dry_run=args.dry_run,
    )
    for warn in warns:
        ctx.plan.note(f"warning: {warn}")
    return ctx


def report_dry_run(ctx: Ctx, args: argparse.Namespace) -> int:
    source_files = set(fsutil.list_files(ctx.source))
    expected = predict.predict(ctx.source, ctx.ident, ctx.answers, ctx.manifest, source_files=source_files)
    pruned = predict.pruned_paths(source_files, ctx.answers, ctx.manifest)
    selfdestruct = predict.template_paths(source_files)
    strips = predict.marker_strips(ctx.source, ctx.answers, ctx.manifest)
    dropped = ctx.manifest.dropped_includes(answers_mod.enabled_components(ctx.answers))
    added = predict.added_paths(source_files, ctx.answers)
    survivors = sorted(source_files - pruned - selfdestruct)
    renamed = [(rel, new) for rel in survivors if (new := _sub(ctx, rel)) != rel]

    print(f"PLAN for {ctx.ident.app_name} ({ctx.ident.bundle_root})")
    print(f"  mode: {'--dest ' + str(args.dest) if args.dest else '--apply'} (dry run — nothing written)")
    print(f"  enabled: {', '.join(sorted(answers_mod.enabled_components(ctx.answers))) or '(none)'}")
    _section("PRUNE files (disabled components / ops flags)", sorted(pruned))
    _section("REMOVE include entries from project.yml", sorted(dropped))
    _section("STRIP Swift marker blocks", strips)
    _section("RENAME paths", [f"{a} -> {b}" for a, b in renamed])
    _section("ADD files", sorted(added))
    _section(f"SELF-DESTRUCT {ctx.source.name}/template", [f"({len(selfdestruct)} files)"])
    destructive = len(pruned) + len(dropped) + len(strips) + len(renamed)
    print(f"\nRESULT: {len(source_files)} files in, {len(expected)} out; "
          f"{destructive} destructive operation(s) beyond the one-shot self-destruct")
    for note in ctx.plan.notes:
        print(f"  note: {note}")
    return 0


def _section(title: str, items: list[str]) -> None:
    print(f"\n{title} ({len(items)})")
    for item in items:
        print(f"  {item}")


def _sub(ctx: Ctx, rel: str) -> str:
    from tmpl.rename import substituter

    return substituter(ctx.ident)(rel)


def run_verify(ctx: Ctx) -> int:
    enabled = answers_mod.enabled_components(ctx.answers)
    result = checks_structure.run(ctx.root, ctx.manifest, ctx.ident, enabled)
    result.extend(checks_generated.run(ctx.root, ctx.manifest, ctx.ident, enabled))
    for warn in result.warns:
        print(f"  warn: {warn}")
    for fail in result.fails:
        print(f"  FAIL: {fail}")
    if result.fails:
        print(f"verify: {len(result.fails)} failure(s) — the generated tree is NOT sound")
        return 1
    print(f"verify: clean ({len(result.warns)} warning(s))")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        root, copied = prepare(args)
        ctx = build_context(args, root)
        if args.dry_run:
            return report_dry_run(ctx, args)
        gitops.run(ctx)
    except GenerateError as exc:
        print(f"\ngenerate: {exc}", file=sys.stderr)
        return 1
    print(f"generated {ctx.ident.app_name} in {root}{' (copy)' if copied else ''}")
    print(
        f"  {len(ctx.plan.deleted)} deleted · {len(ctx.plan.renamed)} renamed · "
        f"{len(ctx.plan.added)} added · {len(ctx.plan.includes_removed)} include entries removed · "
        f"{len(ctx.plan.markers_stripped)} marker blocks stripped"
    )
    for note in ctx.plan.notes:
        print(f"  note: {note}")
    return run_verify(ctx)


if __name__ == "__main__":
    raise SystemExit(main())
