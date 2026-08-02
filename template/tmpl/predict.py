"""Independent oracle: what file set SHOULD a given answers file produce?

Computed from `components.yaml` + the answers alone — never from what the
pipeline actually did. The combo matrix asserts equality in both directions
against the real output, so a prune that deletes one file too many (or too
few) fails CI instead of shipping a half-pruned repo.
"""

from __future__ import annotations

from pathlib import Path

from . import settingsjson
from .answers import Ident, enabled_components, ops
from .context import (
    GENERATED_DOCS,
    ONBOARDING_ANSWERS,
    ONBOARDING_RECORD,
    RELEASE_DEST,
    RELEASE_PAYLOAD,
    TEMPLATE_DIR,
)
from .fsutil import list_files
from .manifest import Manifest
from .rename import substituter


def template_paths(source_files: set[str]) -> set[str]:
    """The generator's own tree, which self-destructs on every successful run."""
    return {f for f in source_files if f == TEMPLATE_DIR or f.startswith(f"{TEMPLATE_DIR}/")}


def marker_strips(source_root: Path, answers: dict, manifest: Manifest) -> list[str]:
    """`path: id xN` for every marker block a disabled component would lose."""
    from .manifest import MARKER_RE

    disabled = manifest.component_ids - enabled_components(answers)
    out: list[str] = []
    for rel, cids in sorted(manifest.all_marker_files.items()):
        path = source_root / rel
        if not (cids & disabled) or not path.is_file():
            continue
        counts: dict[str, int] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            match = MARKER_RE.match(line)
            if match and match.group(2) == "BEGIN" and match.group(1) in disabled:
                counts[match.group(1)] = counts.get(match.group(1), 0) + 1
        out += [f"{rel}: {cid} x{n}" for cid, n in sorted(counts.items())]
    return out


def pruned_paths(source_files: set[str], answers: dict, manifest: Manifest) -> set[str]:
    """Files deleted because a component or an ops flag is off (excludes template/)."""
    enabled = enabled_components(answers)
    gone: set[str] = set()
    for cid in manifest.component_ids - enabled:
        for rel in manifest.owns_dirs(cid):
            gone |= {f for f in source_files if f == rel or f.startswith(f"{rel}/")}
        for rel in manifest.owns_files(cid):
            gone |= {f for f in source_files if f == rel}
    gone |= {f for f in manifest.dropped_includes(enabled) if f in source_files}
    gone |= {f for f in settingsjson.files_removed(ops(answers)) if f in source_files}
    return gone


def removed_paths(source_files: set[str], answers: dict, manifest: Manifest) -> set[str]:
    """Everything the run deletes, before renaming."""
    return pruned_paths(source_files, answers, manifest) | template_paths(source_files)


def added_paths(source_files: set[str], answers: dict) -> set[str]:
    """Everything the run creates that the source tree did not have."""
    added = {ONBOARDING_RECORD, ONBOARDING_ANSWERS, *GENERATED_DOCS}
    if ops(answers).get("ci_system") == "github_actions" and RELEASE_PAYLOAD in source_files:
        added.add(RELEASE_DEST)
    return added


def predict(
    source_root: Path,
    ident: Ident,
    answers: dict,
    manifest: Manifest,
    *,
    source_files: set[str] | None = None,
) -> set[str]:
    """The exact relative-path set a successful generation must produce."""
    files = set(source_files if source_files is not None else list_files(source_root))
    survivors = files - removed_paths(files, answers, manifest)
    sub = substituter(ident)
    renamed = {sub(rel) for rel in survivors}
    # Added files are written after the rename pass, so their paths are final.
    return renamed | added_paths(files, answers)
