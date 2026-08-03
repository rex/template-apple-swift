"""Answers file: validation, dependency rules, identity normalization.

JSON-Schema shape checking lives in `schema.py`; this module owns the domain
rules the schema cannot express — component dependencies from the registry,
bundle-ID nesting, OS-cohort coherence — and turns a validated document into
the `Ident` the rename engine consumes.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from . import schema as schema_mod
from .context import GenerateError

# The identity the template ships with (contracts §1). Every token the rename
# engine substitutes is one of these.
DEFAULT_IDENT = {
    "app_name": "MyApp",
    "bundle_root": "com.example.myapp",
    "team_id": "ABCDE12345",
}

# One OS cohort per row; `deployment` floors drawn from different rows are a
# warning, not an error (contracts §9).
OS_COHORTS = [
    {"ios": "18.0", "macos": "15.0", "watchos": "11.0"},
    {"ios": "26.0", "macos": "26.0", "watchos": "26.0"},
]


@dataclass(frozen=True)
class Ident:
    """Normalized identity: everything the rename engine and verify need."""

    app_name: str
    display_name: str
    bundle_root: str
    team_id: str
    slug: str = field(default="")

    @property
    def app_group(self) -> str:
        return f"group.{self.bundle_root}"

    @property
    def bundle_ids(self) -> dict[str, str]:
        """Target name suffix -> bundle ID. Extensions are host + one segment."""
        root, watch = self.bundle_root, f"{self.bundle_root}.watch"
        return {
            "app": root,
            "mac": root,  # Universal Purchase shares the iOS record
            "watch": watch,
            "complications": f"{watch}.complications",
            "homewidget": f"{root}.homewidget",
            "liveactivity": f"{root}.liveactivity",
            "notificationservice": f"{root}.notificationservice",
            "macwidget": f"{root}.macwidget",
            "tests": f"{root}.tests",
            "uitests": f"{root}.uitests",
        }

    def as_dict(self) -> dict[str, str]:
        return {
            "app_name": self.app_name,
            "display_name": self.display_name,
            "bundle_root": self.bundle_root,
            "team_id": self.team_id,
            "slug": self.slug,
            "app_group": self.app_group,
        }


# --------------------------------------------------------------------------
# loading + domain rules
# --------------------------------------------------------------------------


def load_document(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise GenerateError(f"answers file not found: {path}")
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise GenerateError(f"answers file is not valid YAML: {path}\n  {exc}") from exc
    if not isinstance(doc, dict):
        raise GenerateError(f"answers file must be a YAML mapping: {path}")
    return doc


def component_errors(doc: dict[str, Any], manifest: Any) -> list[str]:
    """Dependency rules from components.yaml `requires`. ERRORS, never fixes."""
    chosen = doc.get("components") or {}
    enabled = {cid for cid, on in chosen.items() if on}
    errs: list[str] = []
    for cid in sorted(enabled):
        for need in manifest.requires(cid):
            if need not in enabled:
                errs.append(
                    f"components: '{cid}' requires '{need}'. "
                    f"Fix: set `components.{need}: true` (or `components.{cid}: false`)."
                )
    for cid in sorted(chosen):
        if cid not in manifest.component_ids:
            known = ", ".join(sorted(manifest.component_ids))
            errs.append(f"components: unknown component '{cid}' — known IDs: {known}")
    return errs


def cohort_warnings(doc: dict[str, Any]) -> list[str]:
    dep = doc.get("deployment") or {}
    if not dep:
        return []
    if any(dep == row for row in OS_COHORTS):
        return []
    rows = " | ".join(str(r) for r in OS_COHORTS)
    return [f"deployment floors {dict(dep)} mix OS cohorts (known-good rows: {rows})"]


def identity(doc: dict[str, Any]) -> Ident:
    ident = doc.get("identity") or {}
    app = ident["app_name"]
    return Ident(
        app_name=app,
        display_name=ident.get("display_name") or app,
        bundle_root=ident["bundle_root"],
        team_id=ident["team_id"],
        slug=app.lower(),
    )


def identity_errors(ident: Ident) -> list[str]:
    """Structural checks the JSON-Schema patterns cannot express."""
    errs: list[str] = []
    ids = ident.bundle_ids
    roots = {ids["app"], ids["watch"]}
    for name, bid in ids.items():
        if name in ("app", "mac"):
            continue
        parent = bid.rsplit(".", 1)[0]
        if parent not in roots:
            errs.append(
                f"identity: derived bundle ID '{bid}' is not its host + exactly one "
                f"segment (ITMS-90347). Check identity.bundle_root."
            )
    if not re.fullmatch(r"[a-z][a-z0-9]*", ident.slug):
        errs.append(f"identity: app_name.lower() ('{ident.slug}') is not a usable slug")
    return errs


def load(path: Path, schema_path: Path, manifest: Any) -> tuple[dict[str, Any], Ident, list[str]]:
    """Validate + normalize. Raises GenerateError listing every violation."""
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    unsupported = schema_mod.verify_support(schema)
    if unsupported:
        raise GenerateError(
            "answers.schema.json uses keywords the built-in validator cannot "
            "honour (silently-ignored constraints are worse than none):\n  "
            + "\n  ".join(unsupported)
        )
    doc = load_document(path)
    errs = schema_mod.validate(doc, schema)
    if not errs:
        doc = schema_mod.apply_defaults(doc, schema)
        errs = component_errors(doc, manifest)
        if not errs:
            ident = identity(doc)
            errs = identity_errors(ident)
    if errs:
        raise GenerateError(
            f"{len(errs)} problem(s) in {path}:\n  " + "\n  ".join(errs)
        )
    return doc, identity(doc), cohort_warnings(doc)


def enabled_components(doc: dict[str, Any]) -> set[str]:
    return {cid for cid, on in (doc.get("components") or {}).items() if on}


def ops(doc: dict[str, Any]) -> dict[str, Any]:
    return doc.get("ops") or {}


def deployment(doc: dict[str, Any]) -> dict[str, str]:
    return doc.get("deployment") or {}
