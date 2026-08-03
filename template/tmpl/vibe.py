"""VIBE.yaml: retune the committed superset policy file for this app.

VIBE.yaml is W2D's file and ships as the superset. The generator does not
rewrite it — it edits the specific keys the answers determine, through
`yamledit` (line surgery), because the file's comments are the policy
documentation and a yaml load/dump round-trip would erase all of them.

The key set is DERIVED from `components.yaml`'s `vibe:` maps rather than
hardcoded, so adding a component's VIBE contribution is a registry edit.
Keys VIBE.yaml does not define are recorded as notes, never invented: a
generator that appends keys to someone else's policy file is a worse failure
than one that leaves a stale value for a human to see.
"""

from __future__ import annotations

from typing import Any

import yaml

from . import yamledit
from .answers import deployment, enabled_components, ops
from .context import VIBE_FILE, Ctx, GenerateError
from .manifest import Manifest

APPLE = "apple"
LIST_BASES = {"platforms": ["iOS"]}
OFF_SCALARS = {"persistence": "none", "monetization": "none"}

# Several logical fields have no single blessed spelling across skeleton
# revisions; the first candidate that exists in the file wins.
DEPLOY_CANDIDATES = {
    "ios": ["apple.deployment_targets.ios", "apple.deployment_target.ios", "apple.deployment.ios", "apple.min_os.ios"],
    "macos": ["apple.deployment_targets.macos", "apple.deployment_target.macos", "apple.deployment.macos", "apple.min_os.macos"],
    "watchos": ["apple.deployment_targets.watchos", "apple.deployment_target.watchos", "apple.deployment.watchos", "apple.min_os.watchos"],
}
OPS_CANDIDATES = {
    "ci_system": ["apple.distribution.ci_system", "apple.ops.ci_system", "ops.ci_system", "apple.ci_system", "ci.system"],
    "signing": ["apple.code_signing", "apple.ops.signing", "ops.signing", "apple.signing"],
    "autonomy": ["workflow.default_autonomy_mode", "ops.autonomy", "autonomy.mode", "project.autonomy"],
}
IDENTITY_CANDIDATES = {
    "name": ["project.name"],
    "display": ["project.display_name", "project.display", "apple.display_name"],
}


def component_fields(manifest: Manifest, enabled: set[str]) -> dict[str, Any]:
    """Dotted-path (relative to `apple:`) -> desired value, from the registry."""
    fields: dict[str, Any] = {}
    for cid in manifest.components:
        for key, value in manifest.vibe(cid).items():
            if key.endswith("+"):
                base = key[:-1]
                fields.setdefault(base, list(LIST_BASES.get(base, [])))
            elif isinstance(value, bool):
                fields.setdefault(key, False)
            elif isinstance(value, list):
                fields.setdefault(key, [])
            else:
                fields.setdefault(key, OFF_SCALARS.get(key, "none"))
    for cid in sorted(enabled):
        for key, value in manifest.vibe(cid).items():
            if key.endswith("+"):
                target = fields[key[:-1]]
                target.extend(v for v in value if v not in target)
            elif isinstance(value, list):
                fields[key] = [*fields[key], *(v for v in value if v not in fields[key])]
            else:
                fields[key] = value
    return fields


def desired(ctx: Ctx) -> list[tuple[list[str], Any]]:
    """(candidate dotted paths, value) for every key this run wants to set."""
    enabled = enabled_components(ctx.answers)
    wants: list[tuple[list[str], Any]] = [
        (IDENTITY_CANDIDATES["name"], ctx.ident.app_name),
        (IDENTITY_CANDIDATES["display"], ctx.ident.display_name),
    ]
    for key, value in sorted(component_fields(ctx.manifest, enabled).items()):
        wants.append(([f"{APPLE}.{key}"], value))
    for key, paths in DEPLOY_CANDIDATES.items():
        floor = deployment(ctx.answers).get(key)
        if floor:
            wants.append((paths, floor))
    for key, paths in OPS_CANDIDATES.items():
        value = ops(ctx.answers).get(key)
        if value is not None:
            wants.append((paths, value))
    return wants


def run(ctx: Ctx) -> None:
    path = ctx.root / VIBE_FILE
    if not path.is_file():
        ctx.plan.note(f"{VIBE_FILE} absent — policy retune skipped")
        return
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    applied: list[tuple[str, Any]] = []
    missing: list[str] = []
    for candidates, value in desired(ctx):
        index = yamledit.index_keys(lines)
        target = next((c for c in candidates if c in index), None)
        if target is None:
            missing.append(candidates[0])
            continue
        if isinstance(value, list):
            yamledit.set_list(lines, index[target], value)
        else:
            yamledit.set_scalar(lines, index[target], value)
        applied.append((target, value))
    text = "".join(lines)
    _verify(path, text, applied)
    if missing:
        ctx.plan.note(f"{VIBE_FILE}: {len(missing)} key(s) not present, left alone: {', '.join(missing)}")
    if text != original:
        ctx.write(path, text)
    ctx.plan.note(f"{VIBE_FILE}: retuned {len(applied)} key(s)")


def _verify(path, text: str, applied: list[tuple[str, Any]]) -> None:
    """Re-parse and confirm every edit landed as the intended value."""
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise GenerateError(f"VIBE.yaml edits produced invalid YAML ({path}): {exc}") from exc
    bad = [
        f"{dotted}: wrote {value!r}, file reads {yamledit.get_path(doc, dotted)!r}"
        for dotted, value in applied
        if yamledit.get_path(doc, dotted) != value
    ]
    if bad:
        raise GenerateError(
            "VIBE.yaml surgical edit did not take effect:\n  " + "\n  ".join(bad)
        )
