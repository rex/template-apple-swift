"""Prune: delete what disabled components own, then strip what they marked.

Three mechanisms, in order of preference (contracts §5/§6):

1. Whole-file / whole-dir deletion  — `owns.dirs`, `owns.files`.
2. Include-entry removal            — delete `xcodegen/components/<x>.yml`
   and its two-line entry in `project.yml`'s `include:` list. This is the
   ONLY edit anyone makes to project.yml; there is no YAML splicing.
3. Swift marker stripping           — `// @template:<id> BEGIN`…`END`.

An `include:` list emptied by (2) is removed outright: XcodeGen rejects a
key whose value parses as null, exactly as it does for a comment-only
`packages:` block.
"""

from __future__ import annotations

import re
from pathlib import Path

from .context import Ctx, GenerateError
from .fsutil import prune_empty_dirs
from .manifest import MARKER_RE

ENTRY_RE = re.compile(r"^(\s*)- path:\s*(\S+)\s*$")
RELATIVE_RE = re.compile(r"^\s*relativePaths:\s*false\s*$")


def run(ctx: Ctx) -> None:
    enabled = {cid for cid, on in (ctx.answers.get("components") or {}).items() if on}
    disabled = sorted(ctx.manifest.component_ids - enabled)
    _delete_owned(ctx, disabled)
    _drop_includes(ctx, enabled)
    _strip_markers(ctx, set(disabled))
    if not ctx.dry_run:
        for gone in prune_empty_dirs(ctx.root):
            ctx.plan.note(f"removed empty directory {gone}")


def _delete_owned(ctx: Ctx, disabled: list[str]) -> None:
    for cid in disabled:
        for rel in ctx.manifest.owned_paths(cid):
            target = ctx.root / rel
            if target.exists():
                ctx.delete(target)
            else:
                ctx.plan.note(f"component '{cid}' owns {rel}, already absent")


def _drop_includes(ctx: Ctx, enabled: set[str]) -> None:
    drop = ctx.manifest.dropped_includes(enabled)
    for rel in drop:
        path = ctx.root / rel
        if path.exists():
            ctx.delete(path)
    project = ctx.root / "project.yml"
    if not project.is_file():
        raise GenerateError("project.yml is missing — nothing to prune includes from")
    text = project.read_text(encoding="utf-8")
    new_text, removed = rewrite_include_list(text, drop)
    ctx.plan.includes_removed.extend(removed)
    if new_text != text:
        ctx.write(project, new_text)


def rewrite_include_list(text: str, drop: list[str]) -> tuple[str, list[str]]:
    """Remove `drop` entries from the `include:` block. Pure; unit-tested.

    Returns the new text and the include paths actually removed. When no
    entries survive, the whole block goes — including the comment paragraph
    immediately above `include:`, which describes only that block.
    """
    lines = text.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if l.rstrip("\n") == "include:"), None)
    if start is None:
        return text, []
    end = len(lines)
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if not stripped or lines[i][:1] in (" ", "\t") or stripped.startswith("#"):
            continue
        end = i
        break

    kept: list[str] = []
    removed: list[str] = []
    pending: list[str] = []
    i = start + 1
    while i < end:
        line = lines[i]
        match = ENTRY_RE.match(line.rstrip("\n"))
        if match is None:
            pending.append(line)
            i += 1
            continue
        pair = [line]
        if i + 1 < end and RELATIVE_RE.match(lines[i + 1].rstrip("\n")):
            pair.append(lines[i + 1])
            i += 2
        else:
            i += 1
        if match.group(2) in drop:
            removed.append(match.group(2))
            pending = []
        else:
            kept.extend(pending)
            kept.extend(pair)
            pending = []
    trailing = [p for p in pending if not p.strip()]

    if not any(ENTRY_RE.match(l.rstrip("\n")) for l in kept):
        head = _strip_leading_comment_block(lines[:start])
        return "".join(head + trailing), removed
    return "".join(lines[:start] + [lines[start]] + kept + trailing + lines[end:]), removed


def _strip_leading_comment_block(head: list[str]) -> list[str]:
    """Drop the contiguous comment paragraph (plus one blank) above `include:`."""
    i = len(head)
    while i > 0 and head[i - 1].lstrip().startswith("#"):
        i -= 1
    while i > 0 and not head[i - 1].strip():
        i -= 1
    return head[:i] + (["\n"] if i > 0 else [])


def _strip_markers(ctx: Ctx, disabled: set[str]) -> None:
    for rel, cids in sorted(ctx.manifest.all_marker_files.items()):
        if not (cids & disabled):
            continue
        path = ctx.root / rel
        if not path.is_file():
            ctx.plan.note(f"marker file already pruned: {rel}")
            continue
        text = path.read_text(encoding="utf-8")
        new_text, stripped = strip_marker_blocks(text, disabled)
        for cid, count in sorted(stripped.items()):
            ctx.plan.markers_stripped.append(f"{rel}: {cid} x{count}")
        if new_text != text:
            ctx.write(path, new_text)


def strip_marker_blocks(text: str, disabled: set[str]) -> tuple[str, dict[str, int]]:
    """Remove BEGIN..END blocks (inclusive) for every disabled ID. Pure."""
    out: list[str] = []
    stripped: dict[str, int] = {}
    skipping: str | None = None
    for line in text.splitlines(keepends=True):
        match = MARKER_RE.match(line.rstrip("\n"))
        if match:
            cid, kind = match.groups()
            if skipping is None and kind == "BEGIN" and cid in disabled:
                skipping = cid
                stripped[cid] = stripped.get(cid, 0) + 1
                continue
            if skipping == cid and kind == "END":
                skipping = None
                continue
        if skipping is None:
            out.append(line)
    if skipping is not None:
        raise GenerateError(f"unbalanced '// @template:{skipping}' block — marker never closed")
    return "".join(out), stripped
