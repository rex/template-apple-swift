#!/usr/bin/env bash
#
# audit-usage-descriptions.sh — an API that needs an NSUsageDescription string
# must find one in a generated Info.plist, and no declared string may be empty.
#
# Adapted from lang-swift-apple/scripts/. The important local difference: every
# Info.plist in this repo is written by `xcodegen generate` from the `info:`
# blocks in project.yml + xcodegen/components/*.yml and is gitignored. So this
# gate is only meaningful AFTER a generate — on a clean tree it finds nothing
# and says so instead of pretending to pass.
#
# Apple rejects the build (not the review) for a missing string, so run this
# before archiving: `make audit`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${1:-$REPO_ROOT}"

red()    { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

failures=0

plist_json() {
    if command -v plutil >/dev/null 2>&1; then
        plutil -convert json -o - "$1"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,plistlib,sys; print(json.dumps(plistlib.load(open(sys.argv[1],"rb"))))' "$1"
    else
        return 2
    fi
}

mapfile -t plists < <(find . -name "Info.plist" \
    -not -path "*/.git/*" -not -path "*/build/*" -not -path "*/DerivedData/*" \
    -not -path "*/Pods/*" -not -path "*/Carthage/*" 2>/dev/null | sort)

if [ ${#plists[@]} -eq 0 ]; then
    yellow "! No Info.plist on disk — they are xcodegen-generated here."
    yellow "  Run 'make bootstrap' (or 'xcodegen generate') first; this gate has"
    yellow "  nothing to check on a clean tree and is NOT claiming a pass."
    exit 0
fi

green "Found ${#plists[@]} generated Info.plist file(s)."

# source pattern -> required Info.plist key
check_api() {
    local pattern="$1" key="$2" hits plist
    # `|| true`: pipefail + a no-match grep would abort the script (set -e).
    hits=$(grep -rEl "\\b$pattern\\b" --include="*.swift" --include="*.m" --include="*.mm" \
        --exclude-dir=.git --exclude-dir=build --exclude-dir=DerivedData \
        . 2>/dev/null | wc -l | tr -d ' ' || true)
    [ "$hits" -gt 0 ] || return 0
    for plist in "${plists[@]}"; do
        if plist_json "$plist" 2>/dev/null | grep -q "\"$key\""; then
            green "  ✓ $pattern → $key declared"
            return 0
        fi
    done
    red "  ✗ $pattern used in $hits file(s) but $key is in no Info.plist"
    red "    Add it to the target's info.properties block in project.yml or the"
    red "    owning xcodegen/components/*.yml fragment — never by hand."
    failures=$((failures + 1))
}

check_api HKHealthStore     NSHealthShareUsageDescription
check_api HKQuantityType    NSHealthShareUsageDescription
check_api HKWorkoutSession  NSHealthUpdateUsageDescription
check_api CLLocationManager NSLocationWhenInUseUsageDescription
check_api AVCaptureDevice   NSCameraUsageDescription
check_api PHPhotoLibrary    NSPhotoLibraryUsageDescription
check_api CBCentralManager  NSBluetoothAlwaysUsageDescription
check_api EKEventStore      NSCalendarsFullAccessUsageDescription
check_api CNContactStore    NSContactsUsageDescription
check_api SFSpeechRecognizer NSSpeechRecognitionUsageDescription
check_api LAContext         NSFaceIDUsageDescription
check_api ATTrackingManager NSUserTrackingUsageDescription
check_api CMMotionActivityManager NSMotionUsageDescription

echo
echo "Checking declared usage strings are non-empty..."
for plist in "${plists[@]}"; do
    if ! json="$(plist_json "$plist" 2>/dev/null)"; then
        red "  ✗ $plist — cannot parse"
        failures=$((failures + 1))
        continue
    fi
    while read -r key; do
        [ -n "$key" ] || continue
        if grep -qE "\"$key\"[[:space:]]*:[[:space:]]*\"\"" <<<"$json"; then
            red "  ✗ $plist — $key is an empty string (Apple rejects this)"
            failures=$((failures + 1))
        fi
    done < <(grep -oE 'NS[A-Za-z]+UsageDescription' <<<"$json" | sort -u)
done

echo
if [ "$failures" -gt 0 ]; then
    red "✗ $failures usage-description issue(s)."
    exit 1
fi
green "✓ Usage descriptions audit passed."
