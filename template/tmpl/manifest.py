"""The component registry (`template/components.yaml`), parsed and validated.

Validation runs against the REAL tree: every `owns.dirs` / `owns.files` entry
must exist, every `marker_files` entry must actually carry a `// @template:<id>`
block for that component, and every `includes:` key must be a file the root
`project.yml` includes. A registry that has drifted from the tree is a fatal
error — silently pruning nothing is how a component "disappears" from a
generated repo while its code stays behind.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from .context import GenerateError

SCHEMA_VERSION = 1
INCLUDE_DIR = "xcodegen/components"
MARKER_RE = re.compile(r"^\s*// @template:([\w-]+) (BEGIN|END)\s*$")

# Components that contribute an xcodegen target (as opposed to capability-only
# components that prune by `rm` alone). Derived, not declared: a component is
# target-bearing iff its include file declares `targets:`.
_TARGETLESS = frozenset({"swiftdata", "store", "account", "health"})


@dataclass
class Manifest:
    path: Path
    doc: dict[str, Any]

    @property
    def components(self) -> dict[str, dict[str, Any]]:
        return self.doc.get("components") or {}

    @property
    def component_ids(self) -> set[str]:
        return set(self.components)

    @property
    def includes(self) -> dict[str, list[str]]:
        return self.doc.get("includes") or {}

    def requires(self, cid: str) -> list[str]:
        return list((self.components.get(cid) or {}).get("requires") or [])

    def owns_dirs(self, cid: str) -> list[str]:
        return list(((self.components.get(cid) or {}).get("owns") or {}).get("dirs") or [])

    def owns_files(self, cid: str) -> list[str]:
        return list(((self.components.get(cid) or {}).get("owns") or {}).get("files") or [])

    def owned_paths(self, cid: str) -> list[str]:
        return self.owns_dirs(cid) + self.owns_files(cid)

    def marker_files(self, cid: str) -> list[str]:
        return list((self.components.get(cid) or {}).get("marker_files") or [])

    def vibe(self, cid: str) -> dict[str, Any]:
        return dict((self.components.get(cid) or {}).get("vibe") or {})

    def asc(self, cid: str) -> dict[str, Any]:
        return dict((self.components.get(cid) or {}).get("asc") or {})

    @property
    def all_marker_files(self) -> dict[str, set[str]]:
        """Relative path -> set of component IDs declaring markers in it."""
        out: dict[str, set[str]] = {}
        for cid in self.components:
            for mf in self.marker_files(cid):
                out.setdefault(mf, set()).add(cid)
        return out

    def target_bearing(self) -> set[str]:
        return {cid for cid in self.components if cid not in _TARGETLESS}

    def include_path(self, name: str) -> str:
        return f"{INCLUDE_DIR}/{name}"

    def kept_includes(self, enabled: set[str]) -> list[str]:
        """Include-file paths surviving, in registry order."""
        return [
            self.include_path(name)
            for name, needs in self.includes.items()
            if all(n in enabled for n in needs)
        ]

    def dropped_includes(self, enabled: set[str]) -> list[str]:
        keep = set(self.kept_includes(enabled))
        return [self.include_path(n) for n in self.includes if self.include_path(n) not in keep]

    def enabled_target_count(self, enabled: set[str]) -> int:
        """MyApp is always present; every enabled target-bearing component adds one."""
        return 1 + len(self.target_bearing() & enabled)


def load(path: Path) -> Manifest:
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise GenerateError(f"components.yaml is not valid YAML: {exc}") from exc
    if not isinstance(doc, dict):
        raise GenerateError(f"components.yaml must be a mapping: {path}")
    got = doc.get("schema_version")
    if got != SCHEMA_VERSION:
        raise GenerateError(
            f"components.yaml schema_version is {got!r}, generator expects "
            f"{SCHEMA_VERSION}. Fix: reconcile the registry with the tree, then "
            f"bump `schema_version` in {path}."
        )
    return Manifest(path=path, doc=doc)


def validate_against_tree(manifest: Manifest, root: Path) -> list[str]:
    """Every declared path must exist and every marker file must carry markers."""
    errs: list[str] = []
    for cid in sorted(manifest.components):
        for need in manifest.requires(cid):
            if need not in manifest.component_ids:
                errs.append(f"{cid}.requires references unknown component '{need}'")
        for d in manifest.owns_dirs(cid):
            if not (root / d).is_dir():
                errs.append(f"{cid}.owns.dirs missing on disk: {d}")
        for f in manifest.owns_files(cid):
            if not (root / f).is_file():
                errs.append(f"{cid}.owns.files missing on disk: {f}")
    errs += _validate_markers(manifest, root)
    errs += _validate_includes(manifest, root)
    return errs


def _validate_markers(manifest: Manifest, root: Path) -> list[str]:
    errs: list[str] = []
    for rel, cids in sorted(manifest.all_marker_files.items()):
        path = root / rel
        if not path.is_file():
            errs.append(f"marker_files missing on disk: {rel} (declared by {sorted(cids)})")
            continue
        found = {m.group(1) for m in (MARKER_RE.match(l) for l in path.read_text().splitlines()) if m}
        for cid in sorted(cids - found):
            errs.append(f"{rel} declares component '{cid}' in marker_files but carries no such block")
        for cid in sorted(found - cids):
            errs.append(f"{rel} carries an undeclared '{cid}' marker block")
    return errs


def _validate_includes(manifest: Manifest, root: Path) -> list[str]:
    errs: list[str] = []
    for name, needs in manifest.includes.items():
        rel = manifest.include_path(name)
        if not (root / rel).is_file():
            errs.append(f"includes: '{name}' has no file at {rel}")
        for need in needs:
            if need not in manifest.component_ids:
                errs.append(f"includes: '{name}' requires unknown component '{need}'")
    declared = {manifest.include_path(n) for n in manifest.includes}
    actual = {str(p.relative_to(root)) for p in (root / INCLUDE_DIR).glob("*.yml")} if (root / INCLUDE_DIR).is_dir() else set()
    for extra in sorted(actual - declared):
        errs.append(f"{extra} exists on disk but is absent from components.yaml `includes:`")
    return errs


def load_validated(path: Path, root: Path) -> Manifest:
    manifest = load(path)
    errs = validate_against_tree(manifest, root)
    if errs:
        raise GenerateError(
            f"{len(errs)} component-registry violation(s) in {path}:\n  " + "\n  ".join(errs)
        )
    return manifest
