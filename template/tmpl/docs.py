"""Regenerate the generated repo's orientation docs from fragments.

`template/docs/fragments/<doc>/NN-<key>.md` — assembled in filename order,
each fragment included iff its `<key>` holds for this run:

    always            unconditional
    <component-id>    that component is enabled
    no-<component-id> that component is disabled
    ci-<value>        ops.ci_system == value
    signing-<value>   ops.signing == value

Fragments carry `{{placeholder}}` tokens rather than literal `MyApp`, because
docs are written AFTER the rename pass — a literal would survive as a residual
token. The assembled text still goes through the substituter as a backstop.

Budgets (agentic-skeleton): AGENTS.md ≤150 lines, PROGRESS.md ≤50. Overrun is
a hard error — a bloated AGENTS.md is the documented way agent context dies.
"""

from __future__ import annotations

import datetime as _dt
from pathlib import Path

from .answers import deployment, enabled_components, ops
from .context import AGENTS_MIRRORS, DOC_BUDGETS, GENERATED_DOCS, Ctx, GenerateError
from .rename import substituter

FRAGMENT_ROOT = "docs/fragments"

EXTENSION_TARGETS = {
    "complications": ("WatchComplications", "watchOS", "complications"),
    "widgets-home": ("HomeWidget", "iOS", "homewidget"),
    "live-activity": ("LiveActivity", "iOS", "liveactivity"),
    "nse": ("NotificationService", "iOS", "notificationservice"),
    "widget-mac": ("MacWidget", "macOS", "macwidget"),
}


def fragments_dir(source: Path) -> Path:
    return source / "template" / FRAGMENT_ROOT


def keep(key: str, enabled: set[str], op: dict) -> bool:
    if key == "always":
        return True
    if key.startswith("no-"):
        return key[3:] not in enabled
    if key.startswith("ci-"):
        return str(op.get("ci_system", "")) == key[3:]
    if key.startswith("signing-"):
        return str(op.get("signing", "")) == key[len("signing-") :]
    return key in enabled


def placeholders(ctx: Ctx) -> dict[str, str]:
    enabled = enabled_components(ctx.answers)
    dep, op = deployment(ctx.answers), ops(ctx.answers)
    return {
        **ctx.ident.as_dict(),
        "ios": dep.get("ios", "18.0"),
        "macos": dep.get("macos", "15.0"),
        "watchos": dep.get("watchos", "11.0"),
        "ci_system": str(op.get("ci_system", "none")),
        "signing": str(op.get("signing", "automatic")),
        "date": _dt.date.today().isoformat(),
        "targets_table": _targets_table(ctx, enabled),
        "components_table": _components_table(ctx, enabled),
        "enabled_list": ", ".join(sorted(enabled)) or "(none — iOS app only)",
        "schemes_list": _schemes(ctx, enabled),
        "readme_platforms": _platforms(enabled),
        "floors": _floors(dep, enabled),
    }


def _floors(dep: dict[str, str], enabled: set[str]) -> str:
    """Only name the floors for platforms this app actually ships to."""
    rows = [("iOS", dep.get("ios", "18.0"))]
    if "mac" in enabled:
        rows.append(("macOS", dep.get("macos", "15.0")))
    if "watch" in enabled:
        rows.append(("watchOS", dep.get("watchos", "11.0")))
    return " · ".join(f"{name} {value}" for name, value in rows)


def _platforms(enabled: set[str]) -> str:
    extra = [name for cid, name in (("mac", "macOS"), ("watch", "watchOS")) if cid in enabled]
    return "".join(f", {name}" for name in extra)


def _targets_table(ctx: Ctx, enabled: set[str]) -> str:
    app, ids = ctx.ident.app_name, ctx.ident.bundle_ids
    rows = [(app, "iOS", "application", ids["app"])]
    if "mac" in enabled:
        rows.append((f"{app}Mac", "macOS", "application", ids["mac"]))
    if "watch" in enabled:
        rows.append((f"{app}Watch", "watchOS", "application", ids["watch"]))
    for cid, (name, platform, idkey) in EXTENSION_TARGETS.items():
        if cid in enabled:
            rows.append((name, platform, "app-extension", ids[idkey]))
    rows.append((f"{app}Tests", "iOS", "bundle.unit-test", ids["tests"]))
    rows.append((f"{app}UITests", "iOS", "bundle.ui-testing", ids["uitests"]))
    head = "| Target | Platform | Type | Bundle ID |\n|---|---|---|---|"
    return "\n".join([head, *(f"| `{n}` | {p} | {k} | `{b}` |" for n, p, k, b in rows)])


def _components_table(ctx: Ctx, enabled: set[str]) -> str:
    head = "| Component | State |\n|---|---|"
    rows = [
        f"| `{cid}` | {'on' if cid in enabled else 'off (pruned)'} |"
        for cid in sorted(ctx.manifest.component_ids)
    ]
    return "\n".join([head, *rows])


def _schemes(ctx: Ctx, enabled: set[str]) -> str:
    app = ctx.ident.app_name
    names = [app, f"{app}Screenshots"]
    if "mac" in enabled:
        names.append(f"{app}Mac")
    if "watch" in enabled:
        names.append(f"{app}Watch")
    return ", ".join(f"`{n}`" for n in names)


def render(ctx: Ctx, doc: str) -> str | None:
    """Assemble one document, or None when it has no fragment directory."""
    directory = fragments_dir(ctx.source) / doc.removesuffix(".md").lower()
    if not directory.is_dir():
        return None
    enabled, op = enabled_components(ctx.answers), ops(ctx.answers)
    chunks: list[str] = []
    for fragment in sorted(directory.glob("*.md")):
        key = fragment.stem.split("-", 1)[1] if "-" in fragment.stem else fragment.stem
        if keep(key, enabled, op):
            chunks.append(fragment.read_text(encoding="utf-8").rstrip("\n"))
    text = "\n\n".join(chunks).rstrip("\n") + "\n"
    for name, value in placeholders(ctx).items():
        text = text.replace(f"{{{{{name}}}}}", value)
    leftover = [w for w in ("{{", "}}") if w in text]
    if leftover:
        raise GenerateError(f"{doc}: unsubstituted placeholder remains — check fragment names")
    return substituter(ctx.ident)(text)


def run(ctx: Ctx) -> None:
    for doc in GENERATED_DOCS:
        text = render(ctx, doc)
        if text is None:
            ctx.plan.note(f"no fragments for {doc} — left as-is")
            continue
        _check_budget(doc, text)
        path = ctx.root / doc
        ctx.write(path, text, added=not path.exists())
        if doc == "AGENTS.md":
            for mirror in AGENTS_MIRRORS:
                mirror_path = ctx.root / mirror
                if mirror_path.exists():
                    ctx.write(mirror_path, text)


def _check_budget(doc: str, text: str) -> None:
    budget = DOC_BUDGETS.get(doc)
    count = len(text.splitlines())
    if budget and count > budget:
        raise GenerateError(
            f"generated {doc} is {count} lines, budget is {budget}. "
            f"Trim template/docs/fragments/{doc.removesuffix('.md').lower()}/."
        )
