"""A JSON-Schema subset validator, in the standard library.

The generator must run from a bare `uv run` with pyyaml as its only
dependency, so `jsonschema` is out. `answers.schema.json` deliberately uses
only the keywords implemented here, and `verify_support()` fails loudly the
day someone adds one this validator would silently ignore — a constraint that
looks enforced but is not is worse than no constraint at all.
"""

from __future__ import annotations

import re
from typing import Any

SUPPORTED_KEYWORDS = frozenset(
    """$schema $id title description type properties required additionalProperties
    pattern enum minLength maxLength default""".split()
)


def verify_support(schema: dict[str, Any], where: str = "$") -> list[str]:
    """Reject schema keywords this validator does not implement."""
    bad = [
        f"{where}: unsupported schema keyword '{k}'"
        for k in schema
        if k not in SUPPORTED_KEYWORDS
    ]
    for name, sub in (schema.get("properties") or {}).items():
        bad += verify_support(sub, f"{where}.{name}")
    return bad


def _type_ok(value: Any, want: str) -> bool:
    if want == "object":
        return isinstance(value, dict)
    if want == "string":
        return isinstance(value, str)
    if want == "boolean":
        return isinstance(value, bool)
    if want == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if want == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if want == "array":
        return isinstance(value, list)
    return True


def validate(value: Any, schema: dict[str, Any], where: str = "answers") -> list[str]:
    """Human-readable violations, deepest path first. Empty list == valid."""
    want = schema.get("type")
    if want and not _type_ok(value, want):
        return [f"{where}: expected {want}, got {type(value).__name__}"]
    errs: list[str] = []
    if "enum" in schema and value not in schema["enum"]:
        errs.append(f"{where}: {value!r} not one of {schema['enum']}")
    if isinstance(value, str):
        errs += _string_errors(value, schema, where)
    if isinstance(value, dict):
        errs += _object_errors(value, schema, where)
    return errs


def _string_errors(value: str, schema: dict[str, Any], where: str) -> list[str]:
    errs: list[str] = []
    pattern = schema.get("pattern")
    if pattern and not re.match(pattern, value):
        errs.append(f"{where}: {value!r} does not match /{pattern}/")
    if "minLength" in schema and len(value) < schema["minLength"]:
        errs.append(f"{where}: shorter than {schema['minLength']} characters")
    if "maxLength" in schema and len(value) > schema["maxLength"]:
        errs.append(f"{where}: longer than {schema['maxLength']} characters")
    return errs


def _object_errors(value: dict[str, Any], schema: dict[str, Any], where: str) -> list[str]:
    errs: list[str] = []
    props = schema.get("properties") or {}
    for req in schema.get("required") or []:
        if req not in value:
            errs.append(f"{where}: missing required key '{req}'")
    if schema.get("additionalProperties") is False:
        for key in value:
            if key not in props:
                known = ", ".join(sorted(props)) or "(none)"
                errs.append(f"{where}: unknown key '{key}' — allowed: {known}")
    for key, sub in props.items():
        if key in value:
            errs += validate(value[key], sub, f"{where}.{key}")
    return errs


def apply_defaults(value: Any, schema: dict[str, Any]) -> Any:
    """Fill every documented default so downstream code never has to guess."""
    if schema.get("type") != "object" or not isinstance(value, dict):
        return value
    out = dict(value)
    for key, sub in (schema.get("properties") or {}).items():
        if key in out:
            out[key] = apply_defaults(out[key], sub)
        elif "default" in sub:
            out[key] = sub["default"]
        elif sub.get("type") == "object":
            filled = apply_defaults({}, sub)
            if filled:
                out[key] = filled
    return out
