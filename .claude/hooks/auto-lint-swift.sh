#!/usr/bin/env bash
# PostToolUse hook — Swift formatting + linting for the file just written.
#
# NET-NEW file (ADR-0008 "Orphan"): the skeleton's auto-lint.sh stays
# byte-identical, and Swift lands in a SECOND PostToolUse group that
# settings.json narrows with `if: "Edit(**/*.swift)"` — the filtering is
# config, not a shell branch (R5 capability audit C1).
#
# Fires on: PostToolUse (matcher Edit|Write, if Edit(**/*.swift))
# Wiring:   async: true, asyncRewake: true, timeout: 120
#           `async` means this can NEVER block a turn. `asyncRewake` means
#           exit 2 wakes an idle session with our stderr attached, which is
#           the only way a slow formatter reports a real problem back.
# Reads:    JSON tool_input.file_path on stdin
# Exits:    0 clean or nothing to do (the overwhelmingly common case)
#           2 SwiftLint still reports errors after --fix (wake, don't block)
#
# Tools are optional by design: a Linux or bare-Mac checkout with neither
# swiftformat nor swiftlint installed exits 0 silently. Missing formatters
# are a local-setup gap, not a code defect, and `make lint` is the real gate.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

FILE=""
if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
fi

case "$FILE" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$FILE" ] || exit 0

# Vendored third-party sources are never reformatted — SnapshotHelper.swift
# is fastlane's file and must stay diffable against upstream.
case "$(basename "$FILE")" in
  SnapshotHelper.swift) exit 0 ;;
esac
case "$FILE" in
  */Generated/*|*/.build/*|*/DerivedData/*) exit 0 ;;
esac

# ── Format (best effort, never fatal) ────────────────────────────────────
if command -v swiftformat >/dev/null 2>&1; then
  swiftformat --quiet "$FILE" >/dev/null 2>&1 || true
fi

if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --fix --quiet --path "$FILE" >/dev/null 2>&1 || true

  # ── Report what --fix could not repair ────────────────────────────────
  # Only `error:` severities wake the session; warnings are noise at this
  # cadence and `make lint` still sees them.
  OUT=$(swiftlint lint --quiet --path "$FILE" 2>/dev/null || true)
  ERRORS=$(printf '%s\n' "$OUT" | grep -E ': error: ' || true)
  if [ -n "$ERRORS" ]; then
    {
      echo "SwiftLint errors remain in $FILE after --fix:"
      printf '%s\n' "$ERRORS" | head -20
      echo "Fix these before the slice is done (\`make lint\` gates on them)."
    } >&2
    exit 2
  fi
fi

exit 0
