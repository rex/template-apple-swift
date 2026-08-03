#!/usr/bin/env bash
#
# write-versions.sh — materialize Config/Versions.xcconfig (ADR-0007).
#
# THE single implementation of the version contract. `make bootstrap`,
# `ci_scripts/ci_post_clone.sh` and the fastlane release lanes all call this
# script; nothing else may write that file and nothing anywhere patches
# project.yml.
#
#   MARKETING_VERSION       := $(cat VERSION)             # plain semver
#   CURRENT_PROJECT_VERSION := $(git rev-list --count HEAD)
#
# Both are overridable from the environment, which is how a CI system with its
# own monotonic counter wires itself in without editing this file:
#
#   CURRENT_PROJECT_VERSION="$CI_BUILD_NUMBER" scripts/apple/write-versions.sh
#
# An .xcconfig is the LOWEST layer of Xcode's build-setting precedence, so both
# keys are deliberately absent from project.yml and every xcodegen/components
# fragment — naming either one there would silently beat this file.
#
# Idempotent: identical content is not rewritten, so xcodegen/Xcode do not see
# a changed file and rebuild the world.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

OUT="Config/Versions.xcconfig"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
yellow() { printf '\033[33m%s\033[0m\n' "$1" >&2; }

# --- MARKETING_VERSION ------------------------------------------------------

marketing="${MARKETING_VERSION:-}"
if [ -z "$marketing" ]; then
    if [ ! -f VERSION ]; then
        red "✗ VERSION is missing — it is the source of truth for MARKETING_VERSION."
        red "  Create it (ADR-0007):  echo 0.1.0 > VERSION"
        exit 1
    fi
    marketing="$(tr -d ' \t\r\n' < VERSION)"
fi

if ! printf '%s' "$marketing" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
    red "✗ MARKETING_VERSION '$marketing' is not plain semver (e.g. 1.4.0)."
    red "  VERSION carries semver only — the MAJOR=/MINOR_BASE= format is dead (ADR-0007)."
    exit 1
fi

# --- CURRENT_PROJECT_VERSION ------------------------------------------------

build="${CURRENT_PROJECT_VERSION:-}"
if [ -z "$build" ]; then
    if git rev-parse --git-dir >/dev/null 2>&1; then
        build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
        if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
            yellow "! shallow clone: 'git rev-list --count HEAD' undercounts, so the build"
            yellow "  number will not be monotonic. Fetch full history, or export"
            yellow "  CURRENT_PROJECT_VERSION from the CI system's own counter."
        fi
    else
        build=""
    fi
fi
if [ -z "$build" ] || [ "$build" = "0" ]; then
    yellow "! no git history here — falling back to CURRENT_PROJECT_VERSION=1."
    yellow "  Fine for a generated tree or a tarball; never ship a build from it."
    build=1
fi

# --- Write ------------------------------------------------------------------

# A heredoc NESTED INSIDE $( ) breaks macOS /bin/bash 3.2 — its substitution
# parser quote-scans the heredoc body, so an apostrophe (or backtick) in a
# comment reads as an unclosed string: "unexpected EOF looking for `'`".
# Render to a temp file instead; cmp keeps the write idempotent.
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp "${TMPDIR:-/tmp}/versions.xcconfig.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
// Version stamp — MACHINE-WRITTEN by scripts/apple/write-versions.sh.
// Do not hand-edit; edit VERSION instead (ADR-0007).
//
// Rewritten in full by \`make bootstrap\`, ci_scripts/ci_post_clone.sh and the
// fastlane release lanes from:
//   MARKETING_VERSION       := \$(cat VERSION)
//   CURRENT_PROJECT_VERSION := \$(git rev-list --count HEAD)
//
// These two keys appear nowhere else. Writing either into project.yml or a
// component .yml would silently override this file, because an .xcconfig is
// the lowest layer of Xcode's build-setting precedence.

MARKETING_VERSION = ${marketing}
CURRENT_PROJECT_VERSION = ${build}
EOF

if [ -f "$OUT" ] && cmp -s "$tmp" "$OUT"; then
    echo "Versions.xcconfig unchanged (${marketing} build ${build})"
    exit 0
fi

mv "$tmp" "$OUT"
echo "Wrote $OUT (MARKETING_VERSION=${marketing} CURRENT_PROJECT_VERSION=${build})"
