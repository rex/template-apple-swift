#!/usr/bin/env bash
#
# statusline.sh — two-row Claude Code status line for this repo.
#
#   row 1   <model> · <repo dir> · <branch> <dirty marker>
#   row 2   [████░░░░░░] 43% · $0.31 · effort: high
#
# Wired only when `ops.statusline: true` at onboarding, because a project
# `statusLine` REPLACES a personal one rather than merging with it (R5-V16).
# The settings fragment is:
#
#   "statusLine": { "type": "command",
#                   "command": "${CLAUDE_PROJECT_DIR}/.claude/statusline.sh",
#                   "padding": 1, "refreshInterval": 10 }
#
# Contract: one JSON object arrives on stdin, one line of output per row.
# Any malformed or empty input exits 0 silently — a status line must never
# be the reason a session looks broken.
#
# BUDGET: < 300 ms. Claude Code debounces status-line updates at 300 ms and
# cancels an in-flight script when a new update arrives, so a slow status
# line is an invisible status line. That rules out, permanently:
#   - xcodebuild / xcodegen / swift / xcrun  (seconds, not milliseconds)
#   - `git status`                           (stats the whole worktree)
#   - anything on the network
# Allowed: one `jq` (or one `python3`) and two plumbing-level git calls.
# Measured on this repo: ~20 ms with jq, ~45 ms on the python3 fallback.
#
# `tput cols` does not work from inside a status-line script — Claude Code
# exports COLUMNS and LINES instead (v2.1.153+). Note also that
# `disableAllHooks: true` disables the status line along with the hooks.

set -euo pipefail

# ── presentation ──────────────────────────────────────────────────────
if [ -n "${NO_COLOR:-}" ]; then
    BOLD='' DIM='' RESET='' CYAN='' MAGENTA='' YELLOW='' GREEN='' RED=''
else
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; YELLOW=$'\033[33m'
    GREEN=$'\033[32m'; RED=$'\033[31m'
fi

SEP=" · "
WIDTH=${COLUMNS:-100}
[ "$WIDTH" -ge 8 ] 2>/dev/null || WIDTH=8
BAR_MIN_WIDTH=40   # below this the bar is dropped and only the % is shown

# ── read stdin, extract fields ────────────────────────────────────────
# One extractor invocation, six fields, in this order:
#   model / repo name / project dir / context % / cost usd / effort level
#
# The separator is US (0x1f), NOT a tab. Tab is IFS *whitespace*, so `read`
# collapses runs of it and one absent field silently shifts every column
# after it — which is how `cost` ends up rendered as a context percentage.
# A non-whitespace IFS character keeps empty fields empty.
payload=$(cat)
[ -n "$payload" ] || exit 0

US=$'\037'

JQ_PROG='[ (.model.display_name // ""),
           (.workspace.repo.name // ""),
           (.workspace.project_dir // .workspace.current_dir // .cwd // ""),
           (.context_window.used_percentage // ""),
           (.cost.total_cost_usd // ""),
           (.effort.level // "") ] | map(tostring) | join("\u001f")'

PY_PROG='
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def g(*path):
    cur = d
    for key in path:
        if not isinstance(cur, dict):
            return ""
        cur = cur.get(key)
        if cur is None:
            return ""
    return cur
ws = d.get("workspace") or {}
print("\x1f".join(str(x) for x in (
    g("model", "display_name"),
    g("workspace", "repo", "name"),
    ws.get("project_dir") or ws.get("current_dir") or d.get("cwd") or "",
    g("context_window", "used_percentage"),
    g("cost", "total_cost_usd"),
    g("effort", "level"),
)))'

if command -v jq >/dev/null 2>&1; then
    fields=$(printf '%s' "$payload" | jq -r "$JQ_PROG" 2>/dev/null) || fields=""
else
    fields=$(printf '%s' "$payload" | python3 -c "$PY_PROG" 2>/dev/null) || fields=""
fi
[ -n "$fields" ] || exit 0

IFS=$US read -r model repo_name project_dir ctx_pct cost effort <<<"$fields"

# ── row assembly ──────────────────────────────────────────────────────
# Truncation happens at append time, never at print time: a segment that
# would overflow is dropped and replaced with an ellipsis. Slicing a
# finished row would cut through either a colour escape or a multi-byte
# block character, and both corrupt the terminal.
plain1=""; color1=""; full1=0
plain2=""; color2=""; full2=0

add1() { # add1 <plain> <colored>
    [ -n "$1" ] || return 0
    [ "$full1" -eq 0 ] || return 0
    local sep=""
    [ -n "$plain1" ] && sep=$SEP
    if [ $(( ${#plain1} + ${#sep} + ${#1} )) -gt "$WIDTH" ]; then
        full1=1
        if [ -z "$plain1" ]; then plain1=${1:0:$((WIDTH - 1))}; color1=$plain1; fi
        plain1+="…"; color1+="…"
        return 0
    fi
    plain1+="$sep$1"; color1+="$sep$2"
}

add2() { # add2 <plain> <colored>
    [ -n "$1" ] || return 0
    [ "$full2" -eq 0 ] || return 0
    local sep=""
    [ -n "$plain2" ] && sep=$SEP
    if [ $(( ${#plain2} + ${#sep} + ${#1} )) -gt "$WIDTH" ]; then
        full2=1
        if [ -z "$plain2" ]; then plain2=${1:0:$((WIDTH - 1))}; color2=$plain2; fi
        plain2+="…"; color2+="…"
        return 0
    fi
    plain2+="$sep$1"; color2+="$sep$2"
}

# ── row 1: model · dir · branch + dirty marker ────────────────────────
dir_label=$repo_name
if [ -z "$dir_label" ] && [ -n "$project_dir" ]; then
    dir_label=$(basename -- "$project_dir")
fi

branch=""; dirty=""
if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
    branch=$(git -C "$project_dir" symbolic-ref --short -q HEAD 2>/dev/null || true)
    if [ -z "$branch" ]; then
        sha=$(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || true)
        if [ -n "$sha" ]; then branch="detached@$sha"; fi
    fi
    # Deliberately `git diff`, never `git status`: this compares index and
    # worktree against HEAD for tracked files only, which is the cheap
    # question. Untracked files stay invisible, and that is the trade.
    if [ -n "$branch" ] \
       && ! git -C "$project_dir" diff --quiet --ignore-submodules HEAD 2>/dev/null; then
        dirty="✱"
    fi
fi

add1 "$model" "${BOLD}${model}${RESET}"
add1 "$dir_label" "${CYAN}${dir_label}${RESET}"
if [ -n "$branch" ] && [ -n "$dirty" ]; then
    add1 "$branch $dirty" "${MAGENTA}${branch}${RESET} ${YELLOW}${dirty}${RESET}"
elif [ -n "$branch" ]; then
    add1 "$branch" "${MAGENTA}${branch}${RESET}"
fi

# ── row 2: context bar · cost · effort ────────────────────────────────
case "$ctx_pct" in
    ''|*[!0-9.]*) ;;   # absent, or not a number — no bar
    *)
        pct=$(printf '%.0f' "$ctx_pct" 2>/dev/null || echo 0)
        if [ "$pct" -gt 100 ]; then pct=100; fi
        if   [ "$pct" -ge 90 ]; then bar_color=$RED
        elif [ "$pct" -ge 70 ]; then bar_color=$YELLOW
        else                         bar_color=$GREEN
        fi
        if [ "$WIDTH" -ge "$BAR_MIN_WIDTH" ]; then
            filled=$(( (pct + 5) / 10 ))
            bar=""
            for ((i = 0; i < 10; i++)); do
                if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
            done
            add2 "[$bar] ${pct}%" "${bar_color}[${bar}]${RESET} ${pct}%"
        else
            add2 "ctx ${pct}%" "${bar_color}ctx ${pct}%${RESET}"
        fi
        ;;
esac

case "$cost" in
    ''|*[!0-9.]*) ;;
    *)
        usd=$(printf '$%.2f' "$cost" 2>/dev/null || echo "")
        add2 "$usd" "${DIM}${usd}${RESET}"
        ;;
esac

if [ -n "$effort" ]; then
    add2 "effort: $effort" "${DIM}effort: ${effort}${RESET}"
fi

# ── emit ──────────────────────────────────────────────────────────────
if [ -n "$color1" ]; then printf '%s\n' "$color1"; fi
if [ -n "$color2" ]; then printf '%s\n' "$color2"; fi
