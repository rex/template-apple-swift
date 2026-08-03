#!/usr/bin/env bash
#
# scan-plist-secrets.sh — Apple-shaped secret scan: plists, xcconfigs, and
# signing material.
#
# detect-secrets and gitleaks are tuned for source and dotfiles; the way an
# Apple repo leaks a credential is different and they miss it:
#
#   * a bundled `Environment.plist` with the broker password in it, shipped
#     inside the .ipa (this is not hypothetical — Pennywise did exactly that,
#     which is why .gitignore names that file),
#   * an `AuthKey_*.p8` / `.p12` / `.mobileprovision` force-added past
#     .gitignore,
#   * an .xcconfig with a token pasted next to DEVELOPMENT_TEAM.
#
# Runs standalone over the whole tree (`make audit`, `make ci-linux`) or with
# explicit paths (pre-commit passes staged files). Pure bash + awk: no plutil,
# no network, works on Linux.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

failures=0

# Files to inspect: arguments win, otherwise everything git can see.
if [ $# -gt 0 ]; then
    files=("$@")
else
    # while-read, not mapfile: macOS /bin/bash is 3.2 and lacks mapfile.
    files=()
    while IFS= read -r _f; do files+=("$_f"); done < <(find . -path ./.git -prune -o -path ./build -prune -o \
        -path ./DerivedData -prune -o -type f -print 2>/dev/null | sed 's|^\./||')
fi

for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"

    case "$base" in
        *.p8|*.p12|*.cer|*.mobileprovision|*.keystore)
            red "✗ $f — signing material must never be committed."
            red "  It is in .gitignore; if it got here, someone used 'git add -f'."
            red "  Rotate the key (revoke in App Store Connect), do not just delete it."
            failures=$((failures + 1))
            continue
            ;;
        Environment.plist)
            red "✗ $f — a bundled Environment.plist ships its contents inside the app."
            red "  Keep runtime configuration in .env / the keychain; commit only the"
            red "  .example alongside it."
            failures=$((failures + 1))
            continue
            ;;
    esac

    case "$base" in
        *.plist|*.xcprivacy|*.xcconfig|*.entitlements) ;;
        *) continue ;;
    esac

    # A credential-looking key with a real value. Placeholders (empty, $(VAR),
    # REPLACE_ME, xxx, the template's own tokens) are fine — they are the
    # documented shape of an example file.
    hits="$(awk '
        function suspicious(k) {
            k = tolower(k)
            return (k ~ /password|passphrase|secret|token|api[_-]?key|apikey|private[_-]?key|credential/)
        }
        function placeholder(v) {
            v = tolower(v)
            gsub(/^[ \t]+|[ \t]+$/, "", v)
            return (v == "" || v ~ /^\$\(/ || v ~ /^\$\{/ || v ~ /replace|example|placeholder|changeme|todo|your[_-]?/ || v ~ /^x+$/)
        }
        # XML plist: <key>NAME</key> then <string>VALUE</string>
        /<key>/ {
            key = $0; sub(/.*<key>/, "", key); sub(/<\/key>.*/, "", key)
            pending = suspicious(key) ? key : ""
            next
        }
        pending != "" && /<string>/ {
            val = $0; sub(/.*<string>/, "", val); sub(/<\/string>.*/, "", val)
            if (!placeholder(val)) printf "%d: %s\n", NR, pending
            pending = ""
            next
        }
        # xcconfig / entitlements-as-text: KEY = VALUE
        /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ {
            key = $0; sub(/[ \t]*=.*/, "", key)
            val = $0; sub(/^[^=]*=[ \t]*/, "", val)
            if (suspicious(key) && !placeholder(val)) printf "%d: %s\n", NR, key
        }
    ' "$f")"

    if [ -n "$hits" ]; then
        red "✗ $f — credential-shaped key(s) with a real value:"
        printf '  %s\n' "$hits" >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    red "✗ $failures file(s) failed the Apple secret scan."
    exit 1
fi

green "✓ No secrets in plists, xcconfigs, or signing material."
