# Release troubleshooting

Symptom → cause → fix. Build failures that never reach fastlane belong to the
`xcode-build-debugger` subagent; this file starts at the archive.

Before anything else, run `make asc-status`. Most "the upload is broken"
reports are a build already sitting in processing, or a version mismatch that
the status dump shows in one line.

## Auth and credentials

| Symptom | Cause | Fix |
|---|---|---|
| Any API lane 401s or "not authorized" | The key is an **Individual** key, not a Team key | Regenerate as a Team key with App Manager/Admin. `references/keys.md` |
| `bootstrap_asc` / `certs` / `notarize` fail while `metadata` works | Same thing: Individual keys cannot use provisioning endpoints or notarytool | As above |
| Fastfile errors before any lane runs | Both `APP_STORE_CONNECT_API_KEY` and `..._P8_PATH` set, or neither | Set exactly one |
| `-authenticationKeyPath` "file not found" | The base64 key was never materialised to disk; the flag needs a real absolute path | The lane does this; if you invoked `xcodebuild` by hand, write the `.p8` to a temp file first |
| Key works locally, fails in CI | Base64 with embedded newlines | `base64 -i AuthKey_X.p8 \| tr -d '\n'` |

## Archive and export

| Symptom | Cause | Fix |
|---|---|---|
| `exportArchive` **exit 70** | Provisioning pairing. The watch app needs the App Group entitlement even before it reads the group, plus `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` = the iOS bundle ID | Fix both in `xcodegen/components/watch.yml`, `make regenerate` |
| gym rejects `export_method` | `ExportOptions.plist` uses Xcode 15's spellings | Legacy spellings only: `app-store`, `developer-id` |
| `assert_export_options` fails the lane | The committed `ExportOptions.plist` drifted from what gym generates | Reconcile them; the assertion exists precisely to catch this |
| "No profiles for … were found" | Automatic signing without `-allowProvisioningUpdates` and the three `-authenticationKey*` flags in **both** `xcargs` and `export_xcargs` | `references/keys.md`; gym has no native flag for this |
| Developer ID build cannot sign | Developer ID certs are not cloud-managed | Switch `ops.signing: match` and run `certs readonly:false` once on a Mac |
| Icon preflight fails | No 1024×1024 master in the `AppIcon` well | Drop it in. `docs/asc-setup.md` §6 |

## Upload and TestFlight

| Symptom | Cause | Fix |
|---|---|---|
| **ITMS-90347** | An extension bundle ID is not its host's ID plus exactly one dot-segment | Fix `PRODUCT_BUNDLE_IDENTIFIER` in the component yml, regenerate, rebuild |
| Watch app missing from the `.ipa`, no build error | It is not a `dependencies:` entry on the iOS app | Add the edge in exactly one file (arrays concatenate with no dedup) |
| Build uploads but never distributes externally | `skip_waiting_for_build_processing` was set, which prevents external distribution | Unset it; let pilot wait |
| External testers never notified | `distribute_external` without `groups`, or `PILOT_DISTRIBUTE_EXTERNAL` set in `.env` flipping `submit_beta_review` | Pass both as lane parameters; never set that env var |
| "Redundant binary upload" | The build number already exists in App Store Connect | Commit first — the build number is `git rev-list --count HEAD` |
| Two builds claim one version | Xcode Cloud and the `beta` lane both archived the commit | Pick one archiver per tag |
| Build stuck in "Processing" | Apple-side, usually minutes; occasionally an export compliance prompt | `make asc-status`; check `uses_non_exempt_encryption` |

## Metadata and review

| Symptom | Cause | Fix |
|---|---|---|
| `precheck` rejects the copy | Metadata problem, not a code problem — it runs at `:error` as a fail-fast gate | Fix `fastlane/metadata/`, re-run `make release` |
| precheck IAP rules error under an API key | Those rules need an Apple ID session | `precheck_include_in_app_purchases: false` |
| deliver hangs waiting for input | The HTML preview confirmation | `force: true` in any non-interactive run |
| Screenshots land in the wrong device slot | Matching is by **pixel resolution**, not folder name | `references/lanes.md` resolution table |
| 2048×2732 shots go to the 13" slot | That resolution is ambiguous | Put `12.9` or `app_ipad_pro_129` in the path |
| Mac or Watch screenshots never appear | snapshot is iOS-simulator only; there is no automation for them | Produce them by hand into `fastlane/screenshots/<locale>/` |
| Mac metadata missing after `metadata` | Universal Purchase needs a second `deliver` run at `platform: "osx"` | Confirm the `mac` component is enabled — the lane gates on it |
| `bootstrap_asc` reports "no app record" | Expected. There is no create-app API endpoint | Create it in the web UI. `docs/asc-setup.md` §3 |
| App Group capability cannot be enabled | The App Group identifier itself is not created by any API | `docs/asc-setup.md` §4 |

## Environment

| Symptom | Cause | Fix |
|---|---|---|
| A mac-only lane misbehaves on Linux instead of refusing | gym does not fail closed on a non-Mac host | The lanes guard with `FastlaneCore::Helper.mac?`; keep the guard |
| Unicode errors in a Linux job | Missing locale | `LC_ALL=C.UTF-8 LANG=C.UTF-8` |
| `bundle exec` cannot find a lane's action | Someone added a plugin | There is no `Pluginfile` by design — core actions only |
| Version in the build does not match `VERSION` | Something wrote `MARKETING_VERSION` outside `Config/Versions.xcconfig` | An `.xcconfig` is the lowest precedence layer; `verify.py` greps for exactly this |

## Escalation

If two hypotheses both fit, stop and run `make asc-status` plus
`bundle exec fastlane bootstrap_asc dry_run:true` — between them they print
the real server-side state, which usually eliminates one branch immediately.

Never retry a failing lane with different credentials, and never more than
once. A lane that failed at auth will fail the same way, and a lane that
failed after upload may have already succeeded server-side.
