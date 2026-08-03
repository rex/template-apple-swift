"""The rename engine: identity tokens in, the new app's identity out.

Contracts §1 fixes the substitution ORDER as longest-first —
`group.com.example.myapp` → `com.example.myapp` → `MyApp` → `myapp` — so
that a shorter token never eats a longer one's prefix. This implementation
gets that guarantee from a single alternation regex applied in ONE pass:
sequential `str.replace` calls would re-scan text they just wrote, so a
`bundle_root` of `com.acme.myapp` would have its own `myapp` segment
rewritten by the fourth pass. One pass, no re-entry, order preserved.

`template/` is never rewritten or renamed: it self-destructs at the end of
the run, and rewriting the running generator mid-flight is a trap.
"""

from __future__ import annotations

import re
from pathlib import Path

from .answers import DEFAULT_IDENT, Ident
from .context import Ctx, GenerateError
from .fsutil import SKIP_DIRS, is_binary, prune_empty_dirs, walk_files

DEFAULT_APP_GROUP = f"group.{DEFAULT_IDENT['bundle_root']}"


def token_map(ident: Ident) -> list[tuple[str, str]]:
    """Longest-first (old, new) pairs. Identical pairs are dropped."""
    pairs = [
        (DEFAULT_APP_GROUP, ident.app_group),
        (DEFAULT_IDENT["bundle_root"], ident.bundle_root),
        (DEFAULT_IDENT["app_name"], ident.app_name),
        (DEFAULT_IDENT["app_name"].lower(), ident.slug),
        (DEFAULT_IDENT["team_id"], ident.team_id),
    ]
    return [(old, new) for old, new in pairs if old != new]


def substituter(ident: Ident):
    """Build a single-pass substitution function for these tokens."""
    pairs = token_map(ident)
    if not pairs:
        return lambda text: text
    table = dict(pairs)
    pattern = re.compile("|".join(re.escape(old) for old, _ in pairs))
    return lambda text: pattern.sub(lambda m: table[m.group(0)], text)


def substitute(text: str, ident: Ident) -> str:
    return substituter(ident)(text)


def run(ctx: Ctx) -> None:
    sub = substituter(ctx.ident)
    if not token_map(ctx.ident):
        ctx.plan.note("identity unchanged (MyApp / com.example.myapp) — rename is a no-op")
        return
    _rewrite_contents(ctx, sub)
    _rename_paths(ctx, sub)
    fix_display_names(ctx)
    if not ctx.dry_run:
        prune_empty_dirs(ctx.root)


def _rewrite_contents(ctx: Ctx, sub) -> None:
    for path in walk_files(ctx.root):
        if is_binary(path):
            continue
        text = path.read_text(encoding="utf-8")
        new_text = sub(text)
        if new_text != text:
            ctx.write(path, new_text)


def _rename_paths(ctx: Ctx, sub) -> None:
    """Deepest-first so a renamed parent never invalidates a queued child."""
    moves: list[tuple[Path, Path]] = []
    for path in walk_files(ctx.root):
        rel = str(path.relative_to(ctx.root))
        new_rel = sub(rel)
        if new_rel != rel:
            moves.append((path, ctx.root / new_rel))
    for src, dst in sorted(moves, key=lambda m: len(m[0].parts), reverse=True):
        if dst.exists():
            raise GenerateError(f"rename collision: {src} -> {dst} (destination already exists)")
        ctx.move(src, dst)


def fix_display_names(ctx: Ctx) -> None:
    """`CFBundleDisplayName` follows display_name, not app_name.

    Both tokens are the literal string `MyApp` in the template (contracts §1),
    so one substitution table cannot produce two different outputs. The token
    pass writes app_name everywhere; this corrects the handful of plist keys
    that actually mean the human-facing name.
    """
    ident = ctx.ident
    if ident.display_name == ident.app_name:
        return
    pattern = re.compile(rf"^(\s*CFBundleDisplayName:\s*){re.escape(ident.app_name)}\s*$")
    for rel in ["project.yml", *(f"xcodegen/components/{p.name}" for p in sorted((ctx.root / "xcodegen/components").glob("*.yml")))]:
        path = ctx.root / rel
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        out, changed = [], False
        for line in lines:
            match = pattern.match(line.rstrip("\n"))
            if match:
                out.append(f"{match.group(1)}{_yaml_scalar(ident.display_name)}\n")
                changed = True
            else:
                out.append(line)
        if changed:
            ctx.write(path, "".join(out))


def _yaml_scalar(value: str) -> str:
    return value if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_ .-]*", value) else f'"{value}"'


def residual_tokens(root: Path, ident: Ident, *, skip_dirs: tuple[str, ...] = SKIP_DIRS) -> list[str]:
    """Every surviving old token, as `path:line: text`. Empty == clean."""
    olds = [old for old, _ in token_map(ident)]
    if not olds:
        return []
    pattern = re.compile("|".join(re.escape(o) for o in olds))
    hits: list[str] = []
    for path in walk_files(root, skip_dirs=skip_dirs):
        if is_binary(path):
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if pattern.search(line):
                hits.append(f"{path.relative_to(root)}:{lineno}: {line.strip()[:110]}")
    for path in walk_files(root, skip_dirs=skip_dirs):
        rel = str(path.relative_to(root))
        if pattern.search(rel):
            hits.append(f"{rel}: residual token in PATH")
    return hits


def assert_clean(ctx: Ctx) -> None:
    if ctx.dry_run:
        return
    hits = residual_tokens(ctx.root, ctx.ident)
    if hits:
        shown = "\n  ".join(hits[:25])
        more = f"\n  ... and {len(hits) - 25} more" if len(hits) > 25 else ""
        raise GenerateError(
            f"{len(hits)} residual template token(s) survived the rename:\n  {shown}{more}"
        )
