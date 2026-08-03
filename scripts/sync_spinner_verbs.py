#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""sync_spinner_verbs.py — materialize the spinner corpus into settings.json.

Claude Code has no file-reference form for `spinnerVerbs.verbs`: the value is
an inline JSON array or nothing (R5-V9). So the curated corpus lives in two
plain-text files and this script is the only thing allowed to copy it in.

    .claude/spinner-verbs.txt  ->  settings.json  spinnerVerbs.verbs
    .claude/spinner-tips.txt   ->  settings.json  spinnerTipsOverride.tips

Corpus format: one entry per line; blank lines and lines whose first
non-space character is `#` are ignored; surrounding whitespace is stripped.

`--check` is the gate (`make spinner-check`, part of `make verify`). It
compares DATA, not bytes, so hand-reindenting settings.json never fails it,
and a sync with no data difference leaves the file untouched rather than
churning formatting this script does not own. Writes use
`json.dump(indent=2)`; key order survives because dicts are ordered and we
mutate in place. A missing spinner key is inserted after `$schema`.
settings.json may legitimately not exist yet: `--check` warns and passes, a
sync says so and stops.

Exit codes: 0 in sync (or not installed) / 1 drift or error / 2 usage.
Usage: sync_spinner_verbs.py [--check] [--root DIR]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

SETTINGS_REL = Path(".claude/settings.json")
VERBS_REL = Path(".claude/spinner-verbs.txt")
TIPS_REL = Path(".claude/spinner-tips.txt")

# Advisory only. Claude Code imposes no length cap (R5-V7); this is the
# "does not wrap in a narrow terminal" budget from contracts §12.
MAX_VERB_LEN = 16
SAMPLE = 6  # entries shown per drift bucket

_TTY = sys.stderr.isatty() and "NO_COLOR" not in os.environ
_R, _G, _Y, _X = ("\033[31m", "\033[32m", "\033[33m", "\033[0m") if _TTY else ("",) * 4


def warn(msg: str) -> None:
    sys.stderr.write(f"{_Y}spinner: {msg}{_X}\n")


def fail(msg: str, code: int = 1) -> int:
    sys.stderr.write(f"{_R}spinner: {msg}{_X}\n")
    return code


# ── corpus ────────────────────────────────────────────────────────────
def read_corpus(path: Path) -> list[str]:
    """Return the non-comment, non-blank, de-duplicated lines of `path`."""
    entries: list[str] = []
    seen: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line in seen:
            continue
        seen.add(line)
        entries.append(line)
    return entries


def lint_verbs(verbs: list[str]) -> list[str]:
    """Advisory corpus-rule complaints (contracts §12). Never blocks."""
    notes: list[str] = []
    if long_ones := [v for v in verbs if len(v) > MAX_VERB_LEN]:
        notes.append(
            f"{len(long_ones)} verb(s) over {MAX_VERB_LEN} chars, may wrap: "
            + ", ".join(long_ones[:SAMPLE])
        )
    if past := [v for v in verbs if v.lower().endswith("ed")]:
        notes.append(
            "gerunds only; these look past-tense: " + ", ".join(past[:SAMPLE])
        )
    return notes


# ── settings.json ─────────────────────────────────────────────────────
def load_settings(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object at the top level")
    return data


def insert_after_schema(settings: dict, key: str, value: dict) -> dict:
    """Insert `key` right after `$schema`, preserving every other position."""
    if "$schema" not in settings:
        settings[key] = value
        return settings
    rebuilt: dict = {}
    for existing_key, existing_value in settings.items():
        rebuilt[existing_key] = existing_value
        if existing_key == "$schema":
            rebuilt[key] = value
    return rebuilt


def block(settings: dict, key: str) -> dict | None:
    value = settings.get(key)
    if value is not None and not isinstance(value, dict):
        raise ValueError(f"settings.json `{key}` must be an object, not {type(value).__name__}")
    return value


def current_list(settings: dict, key: str, field: str) -> list[str] | None:
    holder = block(settings, key) or {}
    value = holder.get(field)
    if value is None:
        return None
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
        raise ValueError(f"settings.json `{key}.{field}` must be an array of strings")
    return value


def apply(settings: dict, verbs: list[str], tips: list[str]) -> dict:
    # Insert tips FIRST: each insertion lands immediately after `$schema`, so
    # inserting verbs second leaves the pair in the order a reader expects
    # (spinnerVerbs, then spinnerTipsOverride).
    if block(settings, "spinnerTipsOverride") is None:
        settings = insert_after_schema(
            settings, "spinnerTipsOverride", {"excludeDefault": False, "tips": []}
        )
    if block(settings, "spinnerVerbs") is None:
        settings = insert_after_schema(settings, "spinnerVerbs", {"mode": "append", "verbs": []})
    verbs_block = settings["spinnerVerbs"]
    verbs_block.setdefault("mode", "append")
    verbs_block["verbs"] = verbs
    tips_block = settings["spinnerTipsOverride"]
    tips_block.setdefault("excludeDefault", False)
    tips_block["tips"] = tips
    return settings


def write_settings(path: Path, settings: dict) -> None:
    path.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ── drift reporting ───────────────────────────────────────────────────
def _bucket(sign: str, verb: str, entries: list[str], width: int = 52) -> None:
    """Tips are whole sentences; a drift summary is not the place for them."""
    shown = ", ".join(
        e if len(e) <= width else e[: width - 1] + "…" for e in entries[:SAMPLE]
    )
    tail = f" (+{len(entries) - SAMPLE} more)" if len(entries) > SAMPLE else ""
    print(f"    {sign} {len(entries)} to {verb}: {shown}{tail}")


def report_drift(label: str, want: list[str], have: list[str] | None) -> bool:
    """Print a summary for one array. Returns True when it drifted."""
    if have is None:
        print(f"  {label}: MISSING from settings.json ({len(want)} to add)")
        return True
    if have == want:
        return False
    missing = [v for v in want if v not in have]
    extra = [v for v in have if v not in want]
    if not missing and not extra:
        print(f"  {label}: same {len(want)} entries, different order")
        return True
    print(f"  {label}: {len(have)} in settings.json, {len(want)} in the corpus")
    if missing:
        _bucket("+", "add", missing)
    if extra:
        _bucket("-", "remove", extra)
    return True


# ── main ──────────────────────────────────────────────────────────────
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="sync_spinner_verbs.py",
        description="Materialize .claude/spinner-*.txt into .claude/settings.json.",
    )
    parser.add_argument("--check", action="store_true", help="report drift, change nothing")
    parser.add_argument("--root", default=None, help="repo root (default: this script's repo)")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parent.parent
    settings_path, verbs_path, tips_path = (root / r for r in (SETTINGS_REL, VERBS_REL, TIPS_REL))
    corpus_missing = [p for p in (verbs_path, tips_path) if not p.is_file()]

    # settings.json is owned elsewhere and may legitimately not exist yet (or
    # ever, if `ops.spinner_flavor` was answered false).
    if not settings_path.is_file():
        if args.check:
            warn(f"{SETTINGS_REL} not found — nothing to check yet. Skipping.")
            return 0
        return fail(f"{SETTINGS_REL} not found; this script only edits an existing file.")

    try:
        settings = load_settings(settings_path)
        if corpus_missing:
            names = ", ".join(str(p.relative_to(root)) for p in corpus_missing)
            if len(corpus_missing) == 2 and not (settings.keys() & {"spinnerVerbs", "spinnerTipsOverride"}):
                warn("spinner flavor is not installed (no corpus, no settings keys). Skipping.")
                return 0
            return fail(f"corpus file(s) missing: {names}. The corpus is the source of truth.")
        have_verbs = current_list(settings, "spinnerVerbs", "verbs")
        have_tips = current_list(settings, "spinnerTipsOverride", "tips")
    except ValueError as exc:
        return fail(str(exc))

    verbs, tips = read_corpus(verbs_path), read_corpus(tips_path)
    if not verbs or not tips:
        empty = "spinner-verbs.txt" if not verbs else "spinner-tips.txt"
        return fail(f"{empty} has no entries; the schema requires minItems: 1.")
    for note in lint_verbs(verbs):
        warn(note)

    in_sync = have_verbs == verbs and have_tips == tips

    if args.check:
        if in_sync:
            print(f"{_G}spinner: in sync{_X} ({len(verbs)} verbs, {len(tips)} tips)")
            return 0
        print(f"{_R}spinner: settings.json has drifted from the corpus{_X}")
        report_drift("spinnerVerbs.verbs", verbs, have_verbs)
        report_drift("spinnerTipsOverride.tips", tips, have_tips)
        print("  fix: make spinner-sync")
        return 1

    if in_sync:
        print(f"{_G}spinner: already in sync{_X} ({len(verbs)} verbs, {len(tips)} tips) — file untouched")
        return 0

    write_settings(settings_path, apply(settings, verbs, tips))
    print(f"{_G}spinner: wrote {len(verbs)} verbs + {len(tips)} tips{_X} to {SETTINGS_REL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
