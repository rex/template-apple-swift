# ADR 0002 — fastlane is the release-automation substrate

- **Status:** Accepted (supersedes the earlier in-planning "raw ASC API
  scripts, no fastlane" decision, reversed by Pierce 2026-08-02)
- **Date:** 2026-08-02
- **Deciders:** @pierce (owner)
- **Scope:** Builds, TestFlight, App Store metadata/screenshots, review
  submission, signing, ASC bootstrap — for the template and every generated app

## Context

Pennywise has zero release automation (archive/upload done by hand in Xcode;
grep confirms no fastlane/altool/notarytool/ASC scripts anywhere). The first
plan draft hand-rolled Python/JWT scripts against the ASC REST API. Pierce
reviewed fastlane's actual surface and reversed: `produce` creates app records
and registers bundle IDs/capabilities — but only with an Apple ID + 2FA
session, because Apple's REST API has no create-app endpoint and `produce`'s
Dev-Portal half still uses the legacy portal (`addAppId.action`). The
API-key-compatible half of that surface is `Spaceship::ConnectAPI::BundleId` /
`BundleIdCapability`, which fastlane exposes as a library even though no lane
action wraps it (see R1 §B). `deliver` gives
metadata-and-screenshots-as-code, `snapshot`/`frameit`
automate screenshot capture, `precheck` lints before review, `pilot` runs
TestFlight, `gym` archives, `match` manages signing for teams, and Spaceship
covers anything bespoke. Hand-rolling that surface violates the
tool-capability-maximization principle (ADR-0006's sibling rule).

## Decision

fastlane, baked in and used to the hilt. Frozen lane names: `bootstrap_asc`,
`beta`, `screenshots`, `metadata`, `release`, `certs`, `status`, `mac_beta`,
`notarize`. Pinned `Gemfile` + committed `Gemfile.lock` + `.ruby-version`.
`Makefile` remains the canonical interface; release verbs delegate to
`bundle exec fastlane <lane>`. Auth via `app_store_connect_api_key`
(`APP_STORE_CONNECT_API_KEY[_P8_PATH]`, `_API_KEY_ID`, `_API_ISSUER`), sourced
from 1Password (`op run`) locally and platform secrets in CI. Default signing
stays automatic/cloud (API key + `-allowProvisioningUpdates`), which works
because Xcode 13+ **cloud-managed distribution certificates** keep the private
key with Apple; note the same trick does not exist for Development or
Developer ID certificates, so the notarised-Mac path is the strongest case for
the `match` opt-in (requires a certs repo + `MATCH_PASSWORD`). gym has no
native flag for this — the lane threads the flags through
`xcargs:`/`export_xcargs:`. API-only lanes
(metadata, status, produce, pilot distribution) work from Linux; build lanes
are macOS-only and fail closed. Xcode Cloud (`ci_scripts/`) remains a supported
CI choice alongside.

## Consequences

- Ruby toolchain is a dependency of every generated repo (documented setup;
  macOS system Ruby 2.6 is insufficient — brew/rbenv).
- App-record creation and metadata push move from "manual" to lanes; the
  irreducibly manual residue (program enrollment, agreements/tax/banking,
  App Review responses) lives in `docs/asc-setup.md`.
- `.p8`/`.p12`/provisioning profiles never enter git; secret-scan covers them.
- `fastlane` is pinned to 2.237.0 and `.ruby-version` to 3.4.x, matching the
  only Ruby line fastlane tests against Xcode 26.x. macOS system Ruby is
  unusable; brew/rbenv/mise required.
- `bootstrap_asc` is partial by construction. App record, App Group, and
  iCloud container creation are documented manual steps in `docs/asc-setup.md`
  with an opt-in Apple-ID escape hatch.
