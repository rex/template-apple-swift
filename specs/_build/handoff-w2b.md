# Handoff W2B → W2C (Makefile targets) and W2A (generator)

W2B owns `fastlane/**`, `Gemfile`, `Gemfile.lock`, `.ruby-version`,
`ExportOptions.plist`, `template/payload/release.yml`,
`docs/release-automation.md`, `docs/asc-setup.md`, `.env.example`. It does not
touch the Makefile. This is the contract W2C should code against.

## 1. Release targets (contracts §8 — frozen 1:1 delegation)

Every target is `cd`-free (fastlane finds `fastlane/` from the repo root) and
needs no extra environment beyond what `.env` / CI secrets provide.

```make
FASTLANE ?= bundle exec fastlane

testflight:      ## Archive the iOS app and ship it to TestFlight
	$(FASTLANE) beta

screenshots:     ## Capture App Store screenshots (iOS simulators)
	$(FASTLANE) screenshots

metadata-push:   ## Push metadata + screenshots to App Store Connect
	$(FASTLANE) metadata

release:         ## precheck, then submit for App Store review
	$(FASTLANE) release

asc-status:      ## Dump App Store Connect state + verify the bundle-ID registry
	$(FASTLANE) status

asc-bootstrap:   ## Register/verify bundle IDs + capabilities in ASC
	$(FASTLANE) bootstrap_asc

notarize-mac:    ## Developer ID build + notarytool
	$(FASTLANE) notarize
```

Two lanes have no frozen Make target: `mac_beta` and `certs`. They are
invoked as `bundle exec fastlane mac_beta` / `bundle exec fastlane certs`.
Adding `mac-testflight` / `certs` aliases is W2C's call — contracts §8 lists
seven targets and I did not invent an eighth. See `questions-w2b.md` Q5.

## 2. Targets W2B depends on existing

- **`make bootstrap`** — `template/payload/release.yml` calls it as the single
  step between `bundle install` and `bundle exec fastlane beta`. It must
  (a) write `Config/Versions.xcconfig` from `VERSION` +
  `git rev-list --count HEAD` and (b) run `xcodegen`. The workflow does a
  full-depth checkout precisely so the rev count is real.
- **`make env`** — skeleton dotenv standard. `.env.example` now exists at the
  repo root; `make env` copies it to `.env` when missing and diffs otherwise.

## 3. Things a Makefile target must NOT do

- Do not `export PILOT_DISTRIBUTE_EXTERNAL`. fastlane maps that one env name
  onto two pilot options with opposite defaults; the `beta` lane passes both
  explicitly. Pass `external:true groups:'…'` as lane arguments instead.
- Do not set `APP_STORE_CONNECT_API_KEY_KEY_ID` / `_ISSUER_ID` / `_KEY`
  (fastlane's own names). The Fastfile reads OUR three names
  (`APP_STORE_CONNECT_API_KEY[_P8_PATH]`, `_API_KEY_ID`, `_API_ISSUER`) and
  passes them as parameters.
- Do not add a `fastlane` install step. `Gemfile.lock` is committed; CI runs
  `bundle install` (frozen) and nothing else.
- Do not re-implement the macOS guard. Every macOS-only lane calls
  `require_macos` itself and exits 1 with an actionable message on Linux, so
  `make testflight` on Linux already fails correctly.

## 4. Notes for W2A (generator)

- `template/payload/release.yml` → `.github/workflows/release.yml` in the
  generated repo when `ops.ci_system: github_actions`. It contains the
  identity tokens `MyApp` (Pushover title) and needs the normal
  longest-first substitution pass.
- `fastlane/**` carries the tokens `com.example.myapp`,
  `group.com.example.myapp`, `MyApp`, `ABCDE12345` and is plain text — it
  must not be on the binary skip-list. `ExportOptions.plist` and
  `.env.example` likewise.
- **No pruning is needed for `fastlane/`.** No component owns any file there
  and there are no markers. Every lane derives the live component set at
  runtime from directories on disk (`COMPONENT_ASC` in `fastlane/Fastfile`,
  whose `dir` values are exactly `components.yaml` `owns.dirs`). If a future
  component changes its `owns.dirs`, that table is the one place to update.
- `fastlane/` now has five Fastfiles (`Fastfile` + four `import`ed
  responsibility splits) because one file blew the 400-line cap:
  `SigningFastfile`, `ShipFastfile`, `MacFastfile`, `ASCFastfile`. Any
  file-manifest or docs fragment that enumerates the repo should list all
  five.
- `fastlane/screenshots/en-US/.gitkeep` exists; `fastlane/screenshots-mac/`
  deliberately does NOT — its absence is the signal that makes the `metadata`
  lane skip the macOS screenshot upload.

## 5. Verified on this Linux box (2026-08-02)

- `bundle install` green (fastlane 2.237.0, Ruby 3.3.6, Bundler 4.0.17).
- `Gemfile.lock` PLATFORMS: `arm64-darwin`, `ruby`, `x86_64-darwin`,
  `x86_64-linux`.
- `bundle exec fastlane lanes` lists all nine frozen lanes.
- `ruby -c` clean on all five Fastfiles.
- Guard paths exercised end-to-end against a scratch tree: `require_macos`,
  `require_mac_component`, `mac_enabled`, `live_components`, `asc_plan`,
  `assert_export_options` (both pass and fail), `icon_preflight` (both empty
  wells and a real 1024 entry), `certs` without `MATCH_GIT_URL`,
  `asc_require_token` without a key.
