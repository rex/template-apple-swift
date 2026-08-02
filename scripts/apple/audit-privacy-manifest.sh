#!/usr/bin/env bash
#
# audit-privacy-manifest.sh — every target ships a valid PrivacyInfo.xcprivacy,
# and every required-reason API the sources touch is declared in one.
#
# Adapted from lang-swift-apple/scripts/. Differences that matter here:
#   * plist parsing goes through plutil when present and python3's plistlib
#     otherwise, so this gate is Linux-runnable (the manifests are the ONE
#     hand-authored plist family in this repo — Info.plist and .entitlements
#     are xcodegen-generated and gitignored, so they cannot be audited from a
#     clean tree at all).
#   * generated/build trees are excluded, including a --dest copy of this repo.
#
# Failing here is preferable to discovering it during App Review: a missing
# privacy manifest is an automatic rejection (required since May 2024).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

failures=0

# plist -> JSON on either OS. plutil is authoritative on macOS; plistlib is the
# same format read by a different parser, which is exactly what we want on CI.
plist_json() {
    if command -v plutil >/dev/null 2>&1; then
        plutil -convert json -o - "$1"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,plistlib,sys; print(json.dumps(plistlib.load(open(sys.argv[1],"rb"))))' "$1"
    else
        return 2
    fi
}

mapfile -t manifests < <(find . -name "PrivacyInfo.xcprivacy" \
    -not -path "*/.git/*" -not -path "*/build/*" -not -path "*/DerivedData/*" \
    -not -path "*/Pods/*" -not -path "*/Carthage/*" 2>/dev/null | sort)

if [ ${#manifests[@]} -eq 0 ]; then
    red "✗ No PrivacyInfo.xcprivacy found — REQUIRED for App Store submission."
    yellow "  Every app and app-extension target needs one at its target root."
    exit 1
fi

green "Found ${#manifests[@]} PrivacyInfo.xcprivacy file(s)."

declared_categories=""
for manifest in "${manifests[@]}"; do
    if ! json="$(plist_json "$manifest" 2>/dev/null)"; then
        red "  ✗ $manifest — cannot parse (plutil/plistlib both failed or absent)"
        failures=$((failures + 1))
        continue
    fi
    for key in NSPrivacyTracking NSPrivacyTrackingDomains NSPrivacyCollectedDataTypes NSPrivacyAccessedAPITypes; do
        case "$json" in
            *"\"$key\""*) ;;
            *) red "  ✗ $manifest — missing required key: $key"; failures=$((failures + 1)) ;;
        esac
    done
    declared_categories="$declared_categories
$(grep -oE 'NSPrivacyAccessedAPICategory[A-Za-z]+' <<<"$json" | sort -u || true)"
done

# Required-reason APIs: if the sources touch one, some manifest must declare it.
echo
echo "Auditing required-reason API usage in source..."
audit_api() {
    local category="$1" pattern="$2" hits
    # `|| true` is load-bearing: `set -o pipefail` + a no-match grep (exit 1)
    # would otherwise abort the whole script under `set -e`. The upstream
    # lang-swift-apple copy of this script has that latent bug.
    hits=$(grep -rEl "$pattern" --include="*.swift" --include="*.m" --include="*.mm" \
        --exclude-dir=.git --exclude-dir=build --exclude-dir=DerivedData \
        . 2>/dev/null | wc -l | tr -d ' ' || true)
    [ "$hits" -gt 0 ] || return 0
    if grep -q "$category" <<<"$declared_categories"; then
        green "  ✓ $category — declared ($hits file(s) touch it)"
    else
        red "  ✗ $category — NOT DECLARED ($hits file(s) touch it)"
        failures=$((failures + 1))
    fi
}

audit_api NSPrivacyAccessedAPICategoryUserDefaults    'UserDefaults'
audit_api NSPrivacyAccessedAPICategoryFileTimestamp   '(creationDate|contentModificationDate|attributesOfItem)'
audit_api NSPrivacyAccessedAPICategorySystemBootTime  '(systemUptime|mach_absolute_time|CACurrentMediaTime)'
audit_api NSPrivacyAccessedAPICategoryDiskSpace       '(volumeAvailableCapacity|volumeTotalCapacity)'
audit_api NSPrivacyAccessedAPICategoryActiveKeyboards 'UITextInputMode'

echo
if [ "$failures" -gt 0 ]; then
    red "✗ $failures privacy-manifest issue(s)."
    exit 1
fi
green "✓ Privacy manifest audit passed."
