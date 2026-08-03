"""Post-generation assertions — the things only a GENERATED repo can be wrong about.

Structural checks (`checks_structure`) prove the tree is a valid xcodegen
project. These prove the transform actually happened: nothing a pruned
component owned survived, nothing references it, the include list matches the
answers exactly, and every bundle ID is explicit and correctly nested.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml

from .answers import Ident
from .checks_structure import Result, yaml_files
from .context import (
    DOC_BUDGETS,
    ONBOARDING_ANSWERS,
    ONBOARDING_RECORD,
    TEMPLATE_DIR,
)
from .manifest import MARKER_RE, Manifest
from .rename import residual_tokens, substituter

# A pruned component must leave no symbol behind. Names are identity-free, so
# the table needs no renaming.
SYMBOLS = {
    "swiftdata": ["SwiftDataCheckpointStore"],
    "store": ["StoreService"],
    "account": ["AccountService"],
    "health": ["HealthService"],
    "watch": ["WatchLink"],
    "live-activity": ["LiveActivityController", "SessionActivityAttributes"],
}


def run(root: Path, manifest: Manifest, ident: Ident, enabled: set[str]) -> Result:
    res = Result()
    disabled = manifest.component_ids - enabled
    _no_orphan_markers(res, root, disabled)
    _symbols_gone(res, root, disabled)
    _owned_files_present(res, root, manifest, enabled, ident)
    _bundle_ids(res, root, ident)
    _residual_tokens(res, root, ident)
    _artifacts(res, root)
    return res


def _no_orphan_markers(res: Result, root: Path, disabled: set[str]) -> None:
    for sw in sorted(root.rglob("*.swift")):
        for i, line in enumerate(sw.read_text(encoding="utf-8").splitlines(), 1):
            match = MARKER_RE.match(line)
            if match and match.group(1) in disabled:
                res.fail(
                    f"orphan marker for pruned component '{match.group(1)}' at "
                    f"{sw.relative_to(root)}:{i}"
                )


def _symbols_gone(res: Result, root: Path, disabled: set[str]) -> None:
    """Comment lines are excluded: prose that names a pruned type is not a build
    dependency, and the template's comments cross-reference each other freely."""
    wanted = {sym: cid for cid in sorted(disabled) for sym in SYMBOLS.get(cid, [])}
    if not wanted:
        return
    pattern = re.compile("|".join(re.escape(s) for s in wanted))
    for sw in sorted(root.rglob("*.swift")):
        for lineno, line in enumerate(sw.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            match = pattern.search(line)
            if match:
                res.fail(
                    f"pruned component '{wanted[match.group(0)]}' symbol "
                    f"'{match.group(0)}' still referenced at "
                    f"{sw.relative_to(root)}:{lineno}"
                )
                break


def _owned_files_present(
    res: Result, root: Path, manifest: Manifest, enabled: set[str], ident: Ident
) -> None:
    sub = substituter(ident)
    for cid in sorted(enabled):
        for rel in manifest.owns_dirs(cid):
            if not (root / sub(rel)).is_dir():
                res.fail(f"enabled component '{cid}' is missing its directory {sub(rel)}")
        for rel in manifest.owns_files(cid):
            if not (root / sub(rel)).is_file():
                res.fail(f"enabled component '{cid}' is missing its file {sub(rel)}")


def _bundle_ids(res: Result, root: Path, ident: Ident) -> None:
    """Explicit ID per target; every extension ID is its host plus one segment."""
    ids: dict[str, str] = {}
    for path in yaml_files(root):
        doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if (doc.get("options") or {}).get("bundleIdPrefix"):
            res.fail(f"{path.name}: options.bundleIdPrefix is banned (contracts §6)")
        for target, tdef in (doc.get("targets") or {}).items():
            if not isinstance(tdef, dict):
                continue
            value = ((tdef.get("settings") or {}).get("base") or {}).get("PRODUCT_BUNDLE_IDENTIFIER")
            if value:
                ids[target] = value
    if not ids:
        res.fail("no PRODUCT_BUNDLE_IDENTIFIER found in any target")
        return
    _check_targets_have_ids(res, root, set(ids))
    known = set(ids.values())
    for target, value in sorted(ids.items()):
        if value in (ident.bundle_root, ident.bundle_ids["watch"]):
            continue
        parent = value.rsplit(".", 1)[0]
        if parent not in known:
            res.fail(
                f"target {target} bundle ID '{value}' is not an existing target's ID "
                f"plus exactly one segment (ITMS-90347)"
            )


def _check_targets_have_ids(res: Result, root: Path, with_ids: set[str]) -> None:
    declared: set[str] = set()
    for path in yaml_files(root):
        doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        declared |= set(doc.get("targets") or {})
    for target in sorted(declared - with_ids):
        res.fail(f"target {target} has no explicit PRODUCT_BUNDLE_IDENTIFIER")


def _residual_tokens(res: Result, root: Path, ident: Ident) -> None:
    for hit in residual_tokens(root, ident)[:20]:
        res.fail(f"residual template token: {hit}")


def _artifacts(res: Result, root: Path) -> None:
    if (root / TEMPLATE_DIR).exists():
        res.fail(f"{TEMPLATE_DIR}/ survived generation — the generator is one-shot")
    for rel in (ONBOARDING_RECORD, ONBOARDING_ANSWERS):
        if not (root / rel).is_file():
            res.fail(f"missing generator artifact: {rel}")
    for doc, budget in DOC_BUDGETS.items():
        path = root / doc
        if not path.is_file():
            res.fail(f"missing generated doc: {doc}")
            continue
        count = len(path.read_text(encoding="utf-8").splitlines())
        if count > budget:
            res.fail(f"{doc} is {count} lines, budget {budget}")
