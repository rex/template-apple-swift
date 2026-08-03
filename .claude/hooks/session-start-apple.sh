#!/usr/bin/env bash
# SessionStart hook — the Apple/template half of session orientation.
#
# This is a NET-NEW file (ADR-0008 "Orphan" class): the skeleton's
# session-start.sh stays byte-identical so `make sync-skeleton` never
# reports drift, and everything Apple-specific lives here as a SECOND
# SessionStart entry. Hook entries merge rather than replace, so both run.
#
# Fires on: SessionStart (matcher startup|resume|clear|fork)
# Emits:    JSON with hookSpecificOutput.additionalContext
# Budget:   < 20 s (settings.json sets timeout: 20). Every external call is
#           timeout-guarded; no xcodebuild, no xcodegen, no network.
# Exits:    ALWAYS 0. Orientation must never be able to fail a session.
#
# What it reports:
#   1. Un-onboarded template banner when template/ still exists.
#   2. Toolchain reality — xcodebuild present (Mac) or absent (Linux/cloud),
#      naming `make ci-linux` as the container-side gate.
#   3. A non-blocking warning below Claude Code v2.1.144, where custom
#      spinnerVerbs leak into the past-tense turn-completion message
#      (contracts §12; fixed upstream in 2.1.144).
#   4. DEVELOPER_DIR pinned through CLAUDE_ENV_FILE when Xcode is present,
#      so every later Bash call agrees on one toolchain.

set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

MIN_CC_VERSION="2.1.144"
ctx=""

add() { ctx+="$1\n"; }

# ── 1. Un-onboarded template banner ──────────────────────────────────────
# template/ is deleted by the generator, so its presence is the single
# reliable signal that this tree is still the template itself.
if [ -d template ] && [ -f template/generate.py ]; then
  add "### UN-ONBOARDED TEMPLATE — run \`/onboard\`"
  add "This repo is still \`template-apple-swift\` itself: every identity token"
  add "is a placeholder (\`MyApp\` / \`com.example.myapp\` / \`ABCDE12345\`) and every"
  add "component is switched on. **Do not start feature work here.** The one job"
  add "in an un-onboarded tree is \`/onboard\` — it asks for identity + components,"
  add "runs \`uv run template/generate.py\`, prunes what you did not pick, renames"
  add "everything, and deletes \`template/\`. Read \`docs/template-guide.md\` before"
  add "changing the machinery itself.\n"
fi

# ── 2. Toolchain reality ─────────────────────────────────────────────────
add "### Apple toolchain"
if command -v xcodebuild >/dev/null 2>&1; then
  xcv="$(timeout 10 xcodebuild -version 2>/dev/null | head -1)"
  add "\`xcodebuild\` present${xcv:+ ($xcv)} — the full gate chain is available."
  if command -v xcodegen >/dev/null 2>&1; then
    add "\`xcodegen\` present. Run \`make regenerate\` after touching \`project.yml\`."
  else
    add "\`xcodegen\` NOT on PATH — \`make regenerate\` will fail. Install it"
    add "(\`brew install xcodegen\`, ≥ 2.46.0) before editing \`project.yml\`."
  fi
else
  add "\`xcodebuild\` is NOT available on this machine, so no target can be built,"
  add "tested, archived or signed here. This is expected on Linux and in cloud"
  add "sessions. The container-side gate is **\`make ci-linux\`** — YAML/plist/"
  add "structure checks, the template's own pytest suite, and the shell/Python"
  add "linters. Anything that needs a real SDK runs on macOS (\`make verify\`)"
  add "or in the \`verify-macos\` workflow. Do not fake a build result."
fi

# Cloud / remote sessions: ~/.claude never arrives, only the clone does.
if [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then
  add "Remote/cloud session: only committed \`.claude/\` config is in effect —"
  add "personal \`~/.claude\` settings, skills and agents did not come along."
fi
add ""

# ── 3. Claude Code version floor (advisory, never blocking) ──────────────
if command -v claude >/dev/null 2>&1; then
  cc_raw="$(timeout 5 claude --version 2>/dev/null | head -1)"
  cc_ver="$(printf '%s' "$cc_raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$cc_ver" ]; then
    lowest="$(printf '%s\n%s\n' "$cc_ver" "$MIN_CC_VERSION" | sort -V | head -1)"
    if [ "$cc_ver" != "$MIN_CC_VERSION" ] && [ "$lowest" = "$cc_ver" ]; then
      add "### Claude Code $cc_ver is below the supported floor ($MIN_CC_VERSION)"
      add "Custom \`spinnerVerbs\` leak into the past-tense turn-completion message"
      add "below $MIN_CC_VERSION (fixed upstream). Everything else works; this is a"
      add "cosmetic warning, not a block. Upgrade when convenient.\n"
    fi
  fi
fi

# ── 4. Pin DEVELOPER_DIR for every later Bash call ───────────────────────
# CLAUDE_ENV_FILE is a path SessionStart may append `export` lines to; they
# apply to all subsequent Bash commands in the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && command -v xcode-select >/dev/null 2>&1; then
  dev_dir="$(timeout 5 xcode-select -p 2>/dev/null || true)"
  if [ -n "$dev_dir" ] && [ -d "$dev_dir" ]; then
    printf 'export DEVELOPER_DIR=%s\n' "$dev_dir" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true
  fi
fi

# ── Emit ─────────────────────────────────────────────────────────────────
[ -z "$ctx" ] && exit 0
if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$ctx" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}' || exit 0
fi
exit 0
