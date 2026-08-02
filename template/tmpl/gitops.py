"""The finalize sequence — the whole generation, in order, once.

    prune → rename → signing xcconfig → VIBE → docs → onboarding record
          → workflows → Claude surfaces → self-destruct → verify

Order is load-bearing. Rename runs after prune so no time is spent rewriting
files that are about to be deleted. Docs run after rename and substitute their
own placeholders. `template/` self-destructs LAST-but-one, so verify runs with
the registry already held in memory rather than read back off a deleted disk.
"""

from __future__ import annotations

import datetime as _dt
import shutil

import yaml

from . import docs, prune, rename, settingsjson, vibe, workflows
from .answers import deployment, enabled_components, ops
from .context import (
    ONBOARDING_ANSWERS,
    ONBOARDING_RECORD,
    SHARED_XCCONFIG,
    TEMPLATE_DIR,
    Ctx,
    GenerateError,
)

TEAM_KEY = "DEVELOPMENT_TEAM"


def run(ctx: Ctx) -> None:
    prune.run(ctx)
    rename.run(ctx)
    write_signing(ctx)
    vibe.run(ctx)
    docs.run(ctx)
    write_onboarding_record(ctx)
    archive_answers(ctx)
    workflows.run(ctx)
    settingsjson.run(ctx)
    rename.assert_clean(ctx)
    self_destruct(ctx)


def write_signing(ctx: Ctx) -> None:
    """`Config/Shared.xcconfig` is the ONE place DEVELOPMENT_TEAM may appear."""
    path = ctx.root / SHARED_XCCONFIG
    if not path.is_file():
        raise GenerateError(
            f"{SHARED_XCCONFIG} is missing — it is the only file allowed to set "
            f"DEVELOPMENT_TEAM (contracts §6)."
        )
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    hit = False
    for i, line in enumerate(lines):
        if line.split("=")[0].strip() == TEAM_KEY:
            lines[i] = f"DEVELOPMENT_TEAM = {ctx.ident.team_id}\n"
            hit = True
    if not hit:
        raise GenerateError(f"{SHARED_XCCONFIG} declares no DEVELOPMENT_TEAM line to rewrite")
    ctx.write(path, "".join(lines))


def archive_answers(ctx: Ctx) -> None:
    """The answers that produced this repo, for `verify.py` and for humans."""
    payload = {
        "generated_at": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        "identity": ctx.ident.as_dict(),
        "components": dict(sorted((ctx.answers.get("components") or {}).items())),
        "deployment": dict(deployment(ctx.answers)),
        "ops": dict(ops(ctx.answers)),
    }
    header = (
        "# Archived onboarding answers — the exact inputs that produced this\n"
        "# repository. `template/verify.py --root .` reads this file to know\n"
        "# which components should be present. Safe to keep; do not hand-edit.\n"
    )
    text = header + yaml.safe_dump(payload, sort_keys=False, default_flow_style=False)
    ctx.write(ctx.root / ONBOARDING_ANSWERS, text, added=True)


def write_onboarding_record(ctx: Ctx) -> None:
    enabled = sorted(enabled_components(ctx.answers))
    disabled = sorted(ctx.manifest.component_ids - set(enabled))
    op, dep = ops(ctx.answers), deployment(ctx.answers)
    ids = ctx.ident.bundle_ids
    rows = "\n".join(f"| `{k}` | `{v}` |" for k, v in ids.items())
    manual = _manual_steps(ctx, op)
    text = f"""# Onboarding record

Generated {_dt.date.today().isoformat()} by `template/generate.py` from
`{ctx.ident.app_name}`'s onboarding answers. This file is the audit trail: it
says what the generator decided so a later reader never has to reverse-engineer
it from the tree.

## Identity

| Field | Value |
|---|---|
| App name | `{ctx.ident.app_name}` |
| Display name | `{ctx.ident.display_name}` |
| Bundle root | `{ctx.ident.bundle_root}` |
| App Group | `{ctx.ident.app_group}` |
| Team ID | `{ctx.ident.team_id}` |
| Slug | `{ctx.ident.slug}` |

## Bundle IDs

Every extension ID is its host ID plus exactly one segment (ITMS-90347).

| Target | Bundle ID |
|---|---|
{rows}

## Components

- **Enabled**: {", ".join(enabled) or "(none)"}
- **Pruned**: {", ".join(disabled) or "(none)"}

## Deployment floors

iOS {dep.get("ios", "-")} · macOS {dep.get("macos", "-")} · watchOS {dep.get("watchos", "-")}

## Ops

| Setting | Value |
|---|---|
| CI system | `{op.get("ci_system", "none")}` |
| Signing | `{op.get("signing", "automatic")}` |
| frameit | `{op.get("frameit", False)}` |
| Spinner flavor | `{op.get("spinner_flavor", True)}` |
| statusLine | `{op.get("statusline", False)}` |
| Autonomy | `{op.get("autonomy", "continue-until-blocked")}` |

## Manual steps still required

{manual}
"""
    ctx.write(ctx.root / ONBOARDING_RECORD, text, added=True)


def _manual_steps(ctx: Ctx, op: dict) -> str:
    steps = [
        f"1. Drop a 1024×1024 master icon into `{ctx.ident.app_name}/Assets.xcassets/AppIcon.appiconset/`.",
        "2. Create the App Store Connect app record and the App Group identifier "
        "(no API endpoint exists for either — see `docs/asc-setup.md`).",
        "3. `make bootstrap` to write `Config/Versions.xcconfig`, then `make build`.",
    ]
    if op.get("signing") == "match":
        steps.append("4. `make certs` to populate the match repo before the first `make testflight`.")
    if op.get("squash_history"):
        steps.append(
            f"{len(steps) + 1}. `ops.squash_history` was requested: squash this repo's history "
            "yourself (`git checkout --orphan`), the generator runs no git commands."
        )
    return "\n".join(steps)


def self_destruct(ctx: Ctx) -> None:
    """One-shot: the generator removes itself from the repo it generated."""
    target = ctx.root / TEMPLATE_DIR
    if not target.is_dir():
        raise GenerateError(f"{TEMPLATE_DIR}/ is already gone — refusing to continue")
    for path in sorted(p for p in target.rglob("*") if p.is_file()):
        ctx.plan.deleted.append(ctx.rel(path))
    if not ctx.dry_run:
        shutil.rmtree(target)
