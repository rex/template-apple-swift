#!/usr/bin/env bash
# PreCompact hook — fires just before Claude Code compacts the conversation.
#
# Compaction defense in this repo is three layers deep:
#   1. On-disk state — TASK_STATE.md / PROGRESS.md are the real memory.
#   2. session-start.sh re-injects them in full on the post-compact resume.
#   3. THIS hook, which points the summarizer at layer 1 before it runs.
#
# Deliberately emits `systemMessage` and nothing else. `systemMessage` is a
# universal hook-output field accepted on every event; earlier revisions of
# this repo's ancestor emitted `hookSpecificOutput.additionalContext` here
# and Claude Code rejected it with a schema error on PreCompact. A hook that
# fails schema validation is worse than a hook that says less, and the
# content it wanted to inject is already covered by layers 1 and 2.
#
# NOTE for maintainers: agentic-skeleton lists `.claude/hooks/pre-compact.sh`
# in sync_skeleton.py's RETIRED set, so `make sync-skeleton --apply` will
# DELETE this file. It is wired in settings.json per contracts §12, so
# re-add it if a sync removes it. See docs/template-guide.md § Hazards.
#
# Fires on: PreCompact
# Budget:   trivial — no subprocess beyond jq.
# Exits:    ALWAYS 0.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

msg="Compacting. Durable state lives on disk, not in this transcript:"
[ -f TASK_STATE.md ] && msg="$msg TASK_STATE.md (slices + handoff),"
[ -f PROGRESS.md ] && msg="$msg PROGRESS.md (session pointer),"
msg="$msg and AGENTS.md. Re-read them after compaction rather than trusting"
msg="$msg the summary; the SessionStart hook re-injects them on resume."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$msg" '{systemMessage:$m, suppressOutput:true}' || exit 0
fi
exit 0
