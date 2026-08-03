#!/usr/bin/env bash
#
# pick-simulator.sh — resolve a simulator NAME for `-destination`.
#
#   scripts/apple/pick-simulator.sh ios     "iPhone 17"
#   scripts/apple/pick-simulator.sh watchos "Apple Watch Series 11 (46mm)"
#
# Prints one device name on stdout; every explanation goes to stderr so the
# caller can do:  -destination "platform=iOS Simulator,name=$(pick-simulator...)"
#
# Simulator names are runner-image-coupled (ADR-0003): `iPhone 15` and
# `Apple Watch Series 9 (45mm)` do not exist on the macos-26 image. So the
# preferred name (Makefile's DEVICE / WATCH_DEVICE, overridable on the command
# line) is honored when it is actually installed, and otherwise this falls back
# to the newest available model rather than failing the build with
# "Unable to find a device matching the provided destination specifier".

set -euo pipefail

usage() {
    echo "usage: pick-simulator.sh <ios|watchos> [preferred device name]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
platform="$1"
preferred="${2:-}"

case "$platform" in
    ios)     runtime_match=".iOS-";     prefix="iPhone" ;;
    watchos) runtime_match=".watchOS-"; prefix="Apple Watch" ;;
    *)       usage ;;
esac

for tool in xcrun python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "pick-simulator: $tool not found — this needs macOS + Xcode." >&2
        exit 1
    }
done

json="$(xcrun simctl list devices available --json 2>/dev/null || echo '{}')"

# Newest = highest runtime version, then highest trailing model number. The
# runtime key looks like com.apple.CoreSimulator.SimRuntime.iOS-26-6.
name="$(RUNTIME_MATCH="$runtime_match" PREFIX="$prefix" PREFERRED="$preferred" \
    python3 -c '
import json, os, re, sys

want = os.environ["RUNTIME_MATCH"]
prefix = os.environ["PREFIX"]
preferred = os.environ["PREFERRED"]
data = json.loads(sys.stdin.read() or "{}").get("devices", {})

def version(rt):
    return tuple(int(n) for n in re.findall(r"\d+", rt.rsplit(".", 1)[-1]))

def model(name):
    return tuple(int(n) for n in re.findall(r"\d+", name)) or (0,)

pool = []
for runtime, devices in data.items():
    if want not in runtime:
        continue
    for dev in devices:
        if dev.get("isAvailable") and dev.get("name"):
            pool.append((version(runtime), dev["name"]))

if preferred and any(n == preferred for _, n in pool):
    print(preferred)
    sys.exit(0)

named = [(v, n) for v, n in pool if n.startswith(prefix)] or pool
if not named:
    sys.exit(1)
print(max(named, key=lambda item: (item[0], model(item[1])))[1])
' <<<"$json")" || {
    echo "pick-simulator: no available $platform simulator found." >&2
    echo "  Install one: Xcode > Settings > Components, or 'xcodebuild -downloadPlatform iOS'." >&2
    exit 1
}

if [ -n "$preferred" ] && [ "$name" != "$preferred" ]; then
    echo "pick-simulator: '$preferred' is not installed — using '$name'." >&2
fi

printf '%s\n' "$name"
