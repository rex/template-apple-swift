## Build system

| Concern | Owner |
|---|---|
| Target/scheme definitions | `project.yml` + `xcodegen/components/*.yml` |
| Team ID | `Config/Shared.xcconfig` (only file allowed to name it) |
| Version + build number | `Config/Versions.xcconfig` (written by CI / `make bootstrap`) |
| Generated plists | `info:` / `entitlements:` blocks in YAML; gitignored on disk |
| Privacy manifests | `*/PrivacyInfo.xcprivacy` — hand-authored, one per bundle |

`make regenerate` reruns XcodeGen. `Generated/BuildInfo.swift` is machine
written by `scripts/apple/generate-build-info.sh` via `options.preGenCommand`.

## Release

Fastlane owns distribution: `beta`, `screenshots`, `metadata`, `release`,
`certs`, `status`, `mac_beta`, `notarize`, `bootstrap_asc`. Make targets
delegate 1:1. See `docs/release-automation.md` and `docs/asc-setup.md`.
