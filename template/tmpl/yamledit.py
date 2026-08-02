"""Surgical, comment-preserving edits to a YAML file's known keys.

VIBE.yaml's comments are load-bearing policy documentation, so a
`yaml.safe_load` → `yaml.dump` round-trip is FORBIDDEN: it would silently
delete every comment, reorder keys and reflow every literal. These helpers
rewrite individual lines in place instead, and callers re-parse the result to
prove the intended value actually landed.

Deliberately narrow: it edits keys that already exist, never creates them.
"""

from __future__ import annotations

import re

KEY_RE = re.compile(r"^(\s*)([A-Za-z_][A-Za-z0-9_.+-]*):(.*)$")
COMMENT_RE = re.compile(r"(\s+#.*)$")
ITEM_RE = re.compile(r"^(\s*)-\s")
BARE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]*$")
RESERVED = {"true", "false", "null", "yes", "no", "on", "off", "none", "~"}


def scalar(value: object) -> str:
    """Render a Python value as a YAML scalar that round-trips to the same type."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if text and BARE_RE.match(text) and text.lower() not in RESERVED:
        try:
            float(text)
        except ValueError:
            return text
    return "'" + text.replace("'", "''") + "'"


def flow_list(values: list[object]) -> str:
    return "[" + ", ".join(scalar(v) for v in values) + "]"


def index_keys(lines: list[str]) -> dict[str, int]:
    """Dotted key path -> line index, for the first occurrence of each path."""
    stack: list[tuple[int, str]] = []
    out: dict[str, int] = {}
    for i, raw in enumerate(lines):
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue
        match = KEY_RE.match(line)
        if match is None:
            continue
        indent, key = len(match.group(1)), match.group(2)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        dotted = ".".join([k for _, k in stack] + [key])
        out.setdefault(dotted, i)
        stack.append((indent, key))
    return out


def _split(line: str) -> tuple[str, str, str, str]:
    """(indent, key, value-text, trailing-comment) for a `key: value` line."""
    match = KEY_RE.match(line.rstrip("\n"))
    if match is None:
        raise ValueError(f"not a key line: {line!r}")
    rest = match.group(3)
    comment_match = COMMENT_RE.search(rest)
    comment = comment_match.group(1) if comment_match else ""
    if comment:
        rest = rest[: -len(comment)]
    return match.group(1), match.group(2), rest.strip(), comment


def set_scalar(lines: list[str], idx: int, value: object) -> bool:
    """Rewrite `key: <value>` in place. Returns True when the text changed."""
    indent, key, _, comment = _split(lines[idx])
    new = f"{indent}{key}: {scalar(value)}{comment}\n"
    if new == lines[idx]:
        return False
    lines[idx] = new
    return True


def block_span(lines: list[str], idx: int) -> tuple[int, int, int]:
    """Extent of the block sequence under key at `idx`: (start, end, indent)."""
    key_indent = len(KEY_RE.match(lines[idx].rstrip("\n")).group(1))
    start = idx + 1
    end = start
    item_indent = key_indent + 2
    for j in range(start, len(lines)):
        stripped = lines[j].strip()
        if not stripped or stripped.startswith("#"):
            end = j + 1 if end > start else start
            continue
        item = ITEM_RE.match(lines[j])
        if item is None or len(item.group(1)) < key_indent:
            break
        item_indent = len(item.group(1))
        end = j + 1
    return start, end, item_indent


def set_list(lines: list[str], idx: int, values: list[object]) -> bool:
    """Rewrite a key's sequence value, keeping flow style flow and block block."""
    indent, key, rest, comment = _split(lines[idx])
    if rest.startswith("[") or not values:
        new = f"{indent}{key}: {flow_list(values)}{comment}\n"
        start, end, _ = block_span(lines, idx) if not rest else (idx + 1, idx + 1, 0)
        if lines[idx] == new and end == start:
            return False
        lines[idx : max(end, idx + 1)] = [new]
        return True
    if rest:  # scalar where a list belongs — normalize to flow style
        lines[idx] = f"{indent}{key}: {flow_list(values)}{comment}\n"
        return True
    start, end, item_indent = block_span(lines, idx)
    pad = " " * item_indent
    replacement = [f"{pad}- {scalar(v)}\n" for v in values]
    if lines[start:end] == replacement:
        return False
    lines[start:end] = replacement
    return True


def get_path(doc: object, dotted: str) -> object:
    """Read a dotted path out of a parsed document; None when absent."""
    node = doc
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node
