"""Structural gate — every Wave-1 check, generalized over identity + components.

This is `specs/_build/gate_w1_reference.py` promoted to a permanent, reusable
gate: same checks, but parameterized so it runs against the committed superset
AND against any generated repo (fewer targets, different identity tokens).
Absent files are skipped rather than failed — pruning is legal — while every
file that IS present must satisfy exactly the Wave-1 rules.
"""

from __future__ import annotations

import json
import plistlib
import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from . import checks_swift
from .answers import Ident
from .manifest import INCLUDE_DIR, Manifest

XCCONFIG_ONLY_KEYS = ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "DEVELOPMENT_TEAM")
CODE_SUFFIXES = (".swift", ".py", ".sh", ".rb")
HARD_LINES, SOFT_LINES = 400, 250


@dataclass
class Result:
    fails: list[str] = field(default_factory=list)
    warns: list[str] = field(default_factory=list)

    def fail(self, msg: str) -> None:
        self.fails.append(msg)

    def warn(self, msg: str) -> None:
        self.warns.append(msg)

    def extend(self, other: "Result") -> "Result":
        self.fails += other.fails
        self.warns += other.warns
        return self


def yaml_files(root: Path) -> list[Path]:
    out = [root / "project.yml"] if (root / "project.yml").is_file() else []
    comp_dir = root / INCLUDE_DIR
    if comp_dir.is_dir():
        out += sorted(comp_dir.glob("*.yml"))
    return out


def run(root: Path, manifest: Manifest, ident: Ident, enabled: set[str]) -> Result:
    res = Result()
    expected_includes = manifest.kept_includes(enabled)
    ymls = yaml_files(root)
    docs = _parse_yaml(res, ymls)
    _no_yaml_markers(res, ymls)
    checks_swift.markers(res, root, manifest)
    _xcconfig_only_keys(res, ymls)
    _includes(res, root, docs, expected_includes)
    _line_caps(res, root)
    checks_swift.forbidden(res, root)
    checks_swift.container_background(res, root)
    _source_paths(res, root, docs)
    _plists(res, root)
    _json(res, root, ident)
    _app_group(res, ymls, ident, manifest, enabled)
    checks_swift.cross_target_api(res, root, ident)
    return res


def _parse_yaml(res: Result, ymls: list[Path]) -> dict[Path, dict]:
    docs: dict[Path, dict] = {}
    for path in ymls:
        try:
            docs[path] = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as exc:
            res.fail(f"YAML parse {path.name}: {exc}")
    return docs


def _no_yaml_markers(res: Result, ymls: list[Path]) -> None:
    for path in ymls:
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"#\s*@template:\w", line):
                res.fail(f"YAML marker survives (markers are Swift-only): {path.name}:{i}")


def _xcconfig_only_keys(res: Result, ymls: list[Path]) -> None:
    for path in ymls:
        code = [l for l in path.read_text(encoding="utf-8").splitlines() if not l.lstrip().startswith("#")]
        for key in XCCONFIG_ONLY_KEYS:
            hits = [l for l in code if key in l]
            if hits:
                res.fail(f"{key} appears in {path.name} (must live only in Config/*.xcconfig): {hits[0].strip()}")


def _includes(res: Result, root: Path, docs: dict[Path, dict], expected: list[str]) -> None:
    project = docs.get(root / "project.yml")
    if project is None:
        res.fail("project.yml missing or unparseable")
        return
    paths: list[str] = []
    for entry in project.get("include") or []:
        if not isinstance(entry, dict) or entry.get("relativePaths") is not False:
            res.fail(f"include entry is not object-form with relativePaths:false: {entry}")
            continue
        paths.append(entry["path"])
        if not (root / entry["path"]).is_file():
            res.fail(f"include file missing: {entry['path']}")
    if sorted(paths) != sorted(expected):
        res.fail(f"include list {sorted(paths)} != expected {sorted(expected)}")


def _line_caps(res: Result, root: Path) -> None:
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in CODE_SUFFIXES or ".git" in path.parts:
            continue
        count = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
        if count > HARD_LINES:
            res.fail(f"line cap: {path.relative_to(root)} = {count} > {HARD_LINES}")
        elif count > SOFT_LINES:
            res.warn(f"soft cap: {path.relative_to(root)} = {count} > {SOFT_LINES}")


def _source_paths(res: Result, root: Path, docs: dict[Path, dict]) -> None:
    for path, doc in docs.items():
        for target, tdef in (doc.get("targets") or {}).items():
            if not isinstance(tdef, dict):
                continue
            for src in tdef.get("sources") or []:
                src = {"path": src} if isinstance(src, str) else src
                rel = src.get("path")
                if rel and not src.get("optional", False) and not (root / rel).exists():
                    res.fail(f"{path.name}: target {target} source path missing: {rel}")


def _plists(res: Result, root: Path) -> None:
    candidates = list(root.rglob("PrivacyInfo.xcprivacy"))
    example = root / "Shared/Env/Environment.example.plist"
    if example.is_file():
        candidates.append(example)
    for path in sorted(candidates):
        try:
            plistlib.loads(path.read_bytes())
        except Exception as exc:  # noqa: BLE001 - plistlib raises many types
            res.fail(f"plist parse {path.relative_to(root)}: {exc}")


def _json(res: Result, root: Path, ident: Ident) -> None:
    assets = root / f"{ident.app_name}/Assets.xcassets"
    candidates = list(assets.rglob("*.json")) if assets.is_dir() else []
    for extra in ("Shared/Resources/Localizable.xcstrings", ".claude/settings.json"):
        if (root / extra).is_file():
            candidates.append(root / extra)
    for path in sorted(candidates):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            res.fail(f"JSON parse {path.relative_to(root)}: {exc}")


def _app_group(res: Result, ymls: list[Path], ident: Ident, manifest: Manifest, enabled: set[str]) -> None:
    want = manifest.enabled_target_count(enabled)
    got = sum(p.read_text(encoding="utf-8").count(ident.app_group) for p in ymls)
    if got != want:
        res.fail(
            f"App Group '{ident.app_group}' appears {got}x in xcodegen YAML; "
            f"expected {want} (one per target that carries it)"
        )
