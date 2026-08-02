#!/usr/bin/env bash
#
# check-no-cocoapods.sh — CocoaPods and Carthage are forbidden here.
#
# Dependencies are Swift Package Manager only, declared in project.yml's
# `packages:` block (currently commented out — see the note at the bottom of
# project.yml explaining why the KEY itself must stay commented). A Podfile
# appearing in this tree means someone ran `pod init` and is about to make the
# generated .xcodeproj unusable, because xcodegen rewrites it wholesale.
#
# Adapted from lang-swift-apple/scripts/. Local difference: `*.xcworkspace` is
# NOT flagged on its own — xcodegen generates one — only when it sits next to a
# Podfile, which is what actually indicates CocoaPods.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()   { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

failures=0

forbid() {
    local label="$1" name="$2" found
    found=$(find . -path ./.git -prune -o -path ./build -prune -o \
        -name "$name" -print 2>/dev/null | head -5)
    if [ -n "$found" ]; then
        red "✗ $label:"
        printf '  %s\n' "$found" >&2
        failures=$((failures + 1))
    fi
}

forbid "CocoaPods Podfile"        "Podfile"
forbid "CocoaPods Podfile.lock"   "Podfile.lock"
forbid "CocoaPods Pods directory" "Pods"
forbid "Carthage Cartfile"        "Cartfile"
forbid "Carthage Cartfile.resolved" "Cartfile.resolved"
forbid "Carthage build directory" "Carthage"

if [ "$failures" -gt 0 ]; then
    red "✗ Forbidden dependency-manager artifacts found ($failures kind(s))."
    red "  Migrate to SPM: declare the package in project.yml::packages and add"
    red "  a dependencies: entry on the target, then re-run 'make bootstrap'."
    exit 1
fi

green "✓ No CocoaPods / Carthage artifacts."
