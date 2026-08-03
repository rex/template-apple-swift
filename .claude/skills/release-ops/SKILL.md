---
name: release-ops
description: Shipping an Apple app from this repo — TestFlight, App Store submission, metadata, screenshots, signing, notarisation and App Store Connect bootstrap. Use when the conversation mentions release, releasing, TestFlight, beta, App Store, App Store Connect, ASC, submit, submission, App Review, fastlane, gym, pilot, deliver, match, precheck, notarize, notarytool, provisioning, codesigning, a .p8 API key, or "ship it".
allowed-tools: Read, Grep, Glob, Bash(make:*), Bash(bundle exec fastlane:*), Bash(git:*)
---

# release-ops

Everything between "the code is done" and "it is in front of a user".

The authoritative prose lives in `docs/release-automation.md` (setup, auth,
lane walkthrough, metadata, screenshots, signing, Xcode Cloud coexistence) and
`docs/asc-setup.md` (the manual residue Apple gives no API for). This skill is
the operator's map: which lane, which failure mode, which of those two
documents answers the question. It does not restate them.

For the step-by-step runbook with preflights, use `/release`. That command is
`disable-model-invocation: true` for a reason — releases are user-initiated.

## When to use this

- Preparing or running a TestFlight build, an App Store submission, or a
  metadata-only push.
- Diagnosing a signing, provisioning, export, upload or App Review failure.
- Setting up App Store Connect for a freshly onboarded app.
- Deciding between automatic (cloud) signing and `match`.
- Anything involving the `.p8` API key, its environment names, or why an
  Individual key does not work.

Not for build failures that never reach fastlane — those are the
`xcode-build-debugger` subagent's job.

## The lane map

Lane names are the API; `make` targets are 1:1 delegates that add nothing but
a memorable verb.

| Make target | Lane | Does | Runs on |
|---|---|---|---|
| `make asc-status` | `status` | Read-only dump: app record, versions, builds + processing state, TestFlight groups, three build numbers side by side | Linux or macOS |
| `make asc-bootstrap` | `bootstrap_asc` | Registers every bundle ID + capability; **checks** for the app record and App Group it cannot create | Linux or macOS |
| `make testflight` | `beta` | icon preflight → export-options assertion → `gym` → `pilot` | macOS only |
| `make screenshots` | `screenshots` | `snapshot` across the simulator matrix (iOS only) | macOS only |
| `make metadata-push` | `metadata` | Text + screenshots, no binary; twice when `mac` is on | Linux or macOS |
| `make release` | `release` | `precheck` at `:error`, then submit for review | Linux or macOS |
| `make notarize-mac` | `notarize` | Developer ID build + notarytool | macOS only |
| — | `mac_beta` | Mac App Store TestFlight | macOS only |
| — | `certs` | `match` certificate sync (keychain import) | macOS only |

`mac_beta` and `certs` have no Make target by contract — run them as
`bundle exec fastlane <lane>`. Every mac-only lane guards itself with an
explicit `FastlaneCore::Helper.mac?` check, because gym does not fail closed
on its own. Lanes that need the `mac` component check for it too.

## The five things that actually go wrong

1. **The API key is an Individual key.** It cannot touch provisioning
   endpoints or notarytool, and the error does not say so. It must be a
   **Team** key with App Manager or Admin.
2. **`bootstrap_asc` "fails" on the app record.** Working as designed — the
   public API has no create-app endpoint. `docs/asc-setup.md` §3.
3. **`PILOT_DISTRIBUTE_EXTERNAL` is set in `.env`.** `distribute_external` and
   `submit_beta_review` share that one variable with opposite defaults. Pass
   both explicitly in the lane; never set the env var.
4. **`ExportOptions.plist` uses the modern method spellings.** gym's whitelist
   wants the legacy `app-store` / `developer-id`, not `app-store-connect` /
   `release-testing`.
5. **Two archivers on one commit.** Pick one per tag. If Xcode Cloud archives
   a commit and `beta` archives it too, build numbers double-increment and App
   Store Connect gets two builds claiming the same version.

## References

| File | Covers |
|---|---|
| `references/lanes.md` | Lane-by-lane semantics: the `pilot` upload/distribute split, deliver's submit flags, Universal Purchase needing two `deliver` calls, how screenshots are actually matched, what has no automation at all |
| `references/keys.md` | The API-key contract and env names, Team vs Individual, automatic vs `match`, how the key reaches `xcodebuild`, what `.gitignore` and `settings.json` already block |
| `references/troubleshooting.md` | Symptom → cause → fix, including exit 70, ITMS-90347, precheck rejections and processing-state stalls |

Version contract, for context in every lane: `MARKETING_VERSION` is `VERSION`
(plain semver), `CURRENT_PROJECT_VERSION` is `git rev-list --count HEAD`, and
both are materialised **only** into `Config/Versions.xcconfig` — by
`ci_scripts/ci_post_clone.sh`, by a release lane, or by `make bootstrap`.
Never patched into `project.yml`, where it would silently outrank the
xcconfig.
