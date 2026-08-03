"""`.claude/settings.json` finishing touches (spinner + statusLine).

W2D owns settings.json in the template and writes placeholder `spinnerVerbs`
/ `spinnerTipsOverride` blocks (gate resolution #14); W2E owns the corpora and
`scripts/sync_spinner_verbs.py`. The generator's job is only to make the
GENERATED repo consistent with `ops.spinner_flavor` / `ops.statusline`:
materialize or remove, never invent policy.

settings.json is strict JSON — no comments are load-bearing — so a
load/dump round-trip is safe here in a way it explicitly is NOT for VIBE.yaml.
"""

from __future__ import annotations

import json
import subprocess
import sys

from .context import (
    SETTINGS_JSON,
    SPINNER_CORPUS,
    SPINNER_SCRIPT,
    STATUSLINE_SCRIPT,
    Ctx,
    GenerateError,
)

SPINNER_KEYS = ("spinnerVerbs", "spinnerTipsOverride")

# contracts §12, verbatim. A project statusLine REPLACES a personal one, so it
# is opt-in and removed outright when `ops.statusline` is false.
STATUSLINE_VALUE = {
    "type": "command",
    "command": "${CLAUDE_PROJECT_DIR}/.claude/statusline.sh",
    "padding": 1,
    "refreshInterval": 10,
}


def files_removed(ops: dict) -> list[str]:
    """Paths deleted purely because an `ops` flag is off. Shared with predict."""
    gone: list[str] = []
    if not ops.get("spinner_flavor", True):
        gone += [*SPINNER_CORPUS, SPINNER_SCRIPT]
    if not ops.get("statusline", False):
        gone.append(STATUSLINE_SCRIPT)
    return gone


def run(ctx: Ctx) -> None:
    ops = ctx.answers.get("ops") or {}
    for rel in files_removed(ops):
        path = ctx.root / rel
        if path.exists():
            ctx.delete(path)
    _edit_settings(ctx, ops)
    if ops.get("spinner_flavor", True):
        _sync_spinner(ctx)


def _edit_settings(ctx: Ctx, ops: dict) -> None:
    path = ctx.root / SETTINGS_JSON
    if not path.is_file():
        ctx.plan.note(f"{SETTINGS_JSON} absent — spinner/statusLine wiring skipped")
        return
    raw = path.read_text(encoding="utf-8")
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GenerateError(f"{SETTINGS_JSON} is not valid JSON: {exc}") from exc
    before = json.dumps(doc, sort_keys=True)
    if not ops.get("spinner_flavor", True):
        for key in SPINNER_KEYS:
            doc.pop(key, None)
    if ops.get("statusline", False):
        doc["statusLine"] = dict(STATUSLINE_VALUE)
    else:
        doc.pop("statusLine", None)
    if json.dumps(doc, sort_keys=True) != before:
        ctx.write(path, json.dumps(doc, indent=2, ensure_ascii=False) + "\n")


def _sync_spinner(ctx: Ctx) -> None:
    script = ctx.root / SPINNER_SCRIPT
    if not script.is_file():
        ctx.plan.note(f"{SPINNER_SCRIPT} absent — spinner corpus not materialized")
        return
    ctx.plan.note(f"ran {SPINNER_SCRIPT} (ops.spinner_flavor: true)")
    if ctx.dry_run:
        return
    proc = subprocess.run(
        [sys.executable, str(script)], cwd=ctx.root, capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise GenerateError(
            f"{SPINNER_SCRIPT} exited {proc.returncode}. Spinner verbs must be "
            f"materialized into {SETTINGS_JSON} before the repo is used.\n"
            f"  stdout: {proc.stdout.strip()[:400]}\n  stderr: {proc.stderr.strip()[:400]}"
        )
