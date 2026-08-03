#!/usr/bin/env bash
#
# ci_post_clone.sh — Xcode Cloud's first hook after the clone.
#
# Xcode Cloud runs `xcodebuild` against a .xcodeproj it expects to already
# exist. This repo's .xcodeproj is a build artifact (ADR-0006), so this script
# has exactly two jobs:
#
#   1. Write Config/Versions.xcconfig — two keys, from VERSION + git
#      (ADR-0007). NOTHING patches project.yml. Pennywise patched
#      MARKETING_VERSION into project.yml with indentation-sensitive awk and
#      shipped the same literal version to TestFlight for months; the xcconfig
#      exists so that class of bug cannot recur.
#   2. Install xcodegen and generate the project.
#
# Xcode Cloud finds this by path convention: `ci_scripts/ci_post_clone.sh` at
# the repo root, executable. It runs with the workspace as the working
# directory, but CI_PRIMARY_REPOSITORY_PATH is authoritative.
#
# Loud on purpose: every decision is echoed, because the only debugging surface
# on a cloud runner is the log.

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO_ROOT"

echo ">>> ci_post_clone: repo root  = $REPO_ROOT"
echo ">>> ci_post_clone: pwd        = $(pwd)"
echo ">>> ci_post_clone: workflow   = ${CI_WORKFLOW:-<none>}"
echo ">>> ci_post_clone: build      = ${CI_BUILD_NUMBER:-<none>}"

# --- 1. Versions ------------------------------------------------------------
#
# Xcode Cloud clones shallowly for most workflows, which makes
# `git rev-list --count HEAD` a lie. CI_BUILD_NUMBER is Xcode Cloud's own
# monotonic counter and is the right answer there; write-versions.sh honors it
# through the documented CURRENT_PROJECT_VERSION override, so the contract
# ("build number = commit count") still holds everywhere it can be true.

if [ -n "${CI_BUILD_NUMBER:-}" ] && \
   [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "true" ]; then
    echo ">>> ci_post_clone: shallow clone — using CI_BUILD_NUMBER=$CI_BUILD_NUMBER"
    export CURRENT_PROJECT_VERSION="$CI_BUILD_NUMBER"
fi

echo ">>> ci_post_clone: writing Config/Versions.xcconfig"
./scripts/apple/write-versions.sh
echo "--- Config/Versions.xcconfig ---"
sed 's/^/    /' Config/Versions.xcconfig

# --- 2. xcodegen ------------------------------------------------------------

if ! command -v xcodegen >/dev/null 2>&1; then
    echo ">>> ci_post_clone: xcodegen not on PATH — installing via Homebrew"
    if ! command -v brew >/dev/null 2>&1; then
        echo "!!! ci_post_clone: brew unavailable; cannot install xcodegen" >&2
        exit 1
    fi
    brew install xcodegen
fi

echo ">>> ci_post_clone: xcodegen $(xcodegen --version 2>/dev/null | tail -1)"
xcodegen generate

echo ">>> ci_post_clone: done — project generated, versions stamped"
