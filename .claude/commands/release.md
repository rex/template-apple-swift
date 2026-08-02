---
description: Ship a build — preflight, TestFlight, metadata, App Store submission, with triage.
argument-hint: beta | metadata | submit | status
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(make:*), Bash(bundle exec fastlane:*), Bash(git:*), Bash(cat:*), Agent
---

Release runbook: **$ARGUMENTS** (default: `beta`).

> Never invoked on your own initiative — `disable-model-invocation: true` is
> deliberate. Every lane below talks to Apple's servers with a Team API key,
> and `submit` puts a build in front of App Review.

## Live context

- Version: !`cat VERSION 2>/dev/null || echo 'VERSION missing'`
- Branch: !`git symbolic-ref --short -q HEAD || echo detached`
- Uncommitted: !`git status --porcelain | wc -l | tr -d ' '` file(s)
- Build number will be: !`git rev-list --count HEAD 2>/dev/null || echo n/a`

## 1. Preflight — all four, before any lane

Stop and report rather than "fixing" anything silently.

1. **VERSION bumped.** `MARKETING_VERSION` comes from `VERSION`, and
   `CURRENT_PROJECT_VERSION` from `git rev-list --count HEAD`. A resubmission
   at an unchanged marketing version is fine; a *new* release at one is not.
   `make bump-patch` / `bump-minor` / `bump-major`, never a hand edit.
2. **CHANGELOG entry** for this version. `fastlane/metadata/en-US/release_notes.txt`
   is what actually reaches TestFlight ("What to Test") and the store listing —
   check it says something a human wrote for *this* build.
3. **Icon present.** A 1024×1024 master in the app's `AppIcon` well. The `beta`
   lane preflights this; catching it here saves the archive.
4. **Clean tree.** Uncommitted changes mean the build number
   (`git rev-list --count HEAD`) does not describe the bits you are shipping.

Then confirm the credentials exist without printing them: the three
`APP_STORE_CONNECT_*` variables, and that the key is a **Team** key —
Individual keys cannot use provisioning endpoints or notarytool, and the
error when they can't is unhelpful. `.claude/settings.json` denies reading
`fastlane/.env*`, `AuthKey_*.p8`, `*.p12` and `*.mobileprovision`; do not try
to route around that.

## 2. The lanes

Make targets are 1:1 delegates. Lane names are the API.

| Ask | Command | What happens |
|---|---|---|
| `status` | `make asc-status` | Read-only: app record, versions, recent builds and processing state, TestFlight groups, and the three build numbers side by side. **Run this first, every time.** |
| `beta` | `make testflight` | icon preflight → export-options assertion → `gym` → `pilot` upload, wait for processing, distribute. |
| external beta | `bundle exec fastlane beta external:true groups:'Friends & Family'` | Triggers beta review. |
| `metadata` | `make metadata-push` | Text + screenshots, no binary. Runs twice when `mac` is on (iOS then `platform: "osx"`, same record). |
| `submit` | `make release` | `precheck` at `:error` as a fail-fast gate, then submits for review with phased release on, automatic release off. |
| screenshots | `make screenshots` | iOS simulators only. No Mac or Watch screenshot automation exists. |
| Mac | `bundle exec fastlane mac_beta` / `make notarize-mac` | Both refuse when the `mac` component is absent. |

Two lanes have no Make target by contract: `mac_beta` and `certs`. Run them
directly.

Never set `PILOT_DISTRIBUTE_EXTERNAL` in `.env`. `distribute_external` and
`submit_beta_review` share that one variable with opposite defaults, so
setting it silently changes a behaviour you did not mean to change.

## 3. Failure triage

Report the failure, name the likely cause, propose one fix. Do not retry a
lane more than once, and never with different credentials.

| Symptom | Where to look |
|---|---|
| `exportArchive` exit 70 | Provisioning pairing. The watch app needs the App Group entitlement and `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` even before it reads the group. Spawn **xcode-build-debugger**. |
| ITMS-90347 at upload | An extension bundle ID is not its host's ID plus exactly one segment. Fix in `xcodegen/components/<id>.yml`, `make regenerate`, rebuild. |
| Watch app missing from the `.ipa` | It is not a `dependencies:` entry on the iOS app. No build error is produced for this, ever. |
| Compile / archive failure | Spawn **xcode-build-debugger** with the `xcodebuild` output. Do not paste a 4,000-line log into the conversation. |
| `precheck` rejects the copy | Metadata problem, not a code problem. `fastlane/metadata/` is the source of truth; fix the text and re-run `make release`. |
| Auth failure on any API lane | Team-vs-Individual key, an expired key, or the wrong issuer ID. `docs/release-automation.md` §2. |
| "no app record" from `bootstrap_asc` | Expected. Apple has no create-app endpoint — `docs/asc-setup.md` §3. |
| Signing / certificate churn | `docs/release-automation.md` §6, and `bundle exec fastlane certs` when `match` is on. |

Deeper reading, in order: `docs/release-automation.md` (setup, auth, lane
walkthrough, metadata, screenshots, signing, Xcode Cloud coexistence), then
`docs/asc-setup.md` (the manual residue), then the `release-ops` skill's
`references/` for the long-form troubleshooting.

## 4. Close out

Report the build number that shipped, where it landed (TestFlight internal /
external / review), and what is still manual. If a version was bumped, make
sure the bump and the CHANGELOG entry are committed — a released build whose
version only exists in someone's working tree is a build you cannot reproduce.
