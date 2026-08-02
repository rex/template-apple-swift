# R1 — fastlane deep-dive

> Research date: **2026-08-02**. Pinned facts verified against fastlane `master`
> source, RubyGems, docs.fastlane.tools, Apple developer docs, and one
> **empirical install** (fastlane 2.237.0 on Ubuntu 24.04 / Ruby 3.3.6 /
> Bundler 4.0.17) run inside this session. Read against `contracts.md` §8 and
> ADR-0002.

---

## Verdicts

### A. Toolchain pin, Ruby, Linux

**V1 — Pin `fastlane 2.237.0` (released 2026-07-05).**
Evidence: RubyGems version index (`GET /api/v1/versions/fastlane.json`) — `2.237.0 / 2026-07-05`,
prior `2.236.1 / 2026-06-11`, `2.236.0 / 2026-06-08`. `spec.required_ruby_version = '>= 3.0'`
in `fastlane.gemspec` (raised from `>= 2.7` at 2.235.0, 2026-05-26).
**Confidence: high.**

**V2 — `.ruby-version` should be `3.4.x`, not `3.3.x` (amend contracts §8).**
Evidence: fastlane's own `.github/workflows/ci.yml` on master runs this matrix:
```
{ xcode: '16.4.0', ruby: '3.1' | '3.2' | '3.3' | '3.4', os: 'macos-15' }
{ xcode: '26.5',   ruby: '3.4', rubyopt: '-W0', os: 'macos-26' }
{ xcode: '26.6',   ruby: '3.4', rubyopt: '-W0', os: 'macos-26' }
{ xcode: '26.6',   ruby: '4.0', rubyopt: '-W0', os: 'macos-26' }
{ xcode: '',       ruby: '3.2', os: 'windows-2022' }
{ xcode: '',       ruby: '3.0', os: 'ubuntu-24.04' }
```
Ruby **3.4** is the only version fastlane tests against Xcode 26.x. Install docs
say "supports Ruby 3.0 or newer, but **prefers Ruby 3.3 or greater**" and emit
`WARNING: … fastlane will soon require Ruby 3.3.0 or newer` — i.e. 3.3 sits
exactly on the announced floor. Ruby 3.4.10 (2026-06-30) is current-stable-LTS;
Ruby 4.0.0 shipped 2025-12-25 (4.0.6 as of 2026-07-14) and fastlane already
tests it, but the gemspec still carries 4.0/4.1 stdlib-extraction shims
(`irb`, `logger`, `benchmark`, `ostruct`) — treat 4.0 as "works, not the
default". **Confidence: high.**

**V3 — fastlane genuinely runs on Linux; API-only lanes are Linux-clean. Empirically verified.**
Evidence (this session): `bundle install` of `fastlane 2.237.0` succeeded on
Ubuntu 24.04 / Ruby 3.3.6; `bundle exec fastlane --version` → `fastlane 2.237.0`;
a real lane executed (`host_os=linux`, `FastlaneCore::Helper.mac? == false`).
`app_store_connect_api_key(key_content: <base64 p8>, is_key_content_base64: true)`
ran green on Linux and set `Spaceship::ConnectAPI.token` (JWT text length 291).
fastlane's own CI includes an `ubuntu-24.04` row. **Confidence: high (empirical).**

**V3a — Linux needs `LC_ALL`/`LANG` set to a UTF-8 locale.** Observed verbatim:
`WARNING: fastlane requires your locale to be set to UTF-8.` Every Linux CI job
must export `LC_ALL=C.UTF-8 LANG=C.UTF-8` (or `en_US.UTF-8`). **Confidence: high (empirical).**

**V3b — Build lanes do NOT fail closed on Linux.** `build_app` on Linux died with
`Project file not found at path …` (an option-validation error), not a
"requires macOS" guard. gym has no platform guard. Our Fastfile must add an
explicit `UI.user_error!` guard. **Confidence: high (empirical).**

**V3c — `pilot` *upload* on Linux needs Transporter; `pilot` *distribute* does not.**
Docs: "To upload binaries from Linux: have the package file and the
`AppStoreInfo.plist` file in the same location on disk; make sure you have
Transporter on Linux installed; set `FASTLANE_ITUNES_TRANSPORTER_USE_SHELL_SCRIPT=true`
and `FASTLANE_ITUNES_TRANSPORTER_PATH=/usr/local/itms`." gym gained a
`generate_appstore_info` option that produces that plist. `distribute_only: true`
is pure ASC API → no Transporter. Our design never uploads from Linux, so this
is a documented non-path. **Confidence: high.**

---

### B. `produce` / `bootstrap_asc` — the load-bearing negative result

**V4 — `produce` CANNOT authenticate with an App Store Connect API key. Both halves require an Apple ID + 2FA session.** This breaks `bootstrap_asc` as specified.
Evidence, source-level:
- `produce/lib/produce/developer_center.rb` → `def login; Spaceship.login(Produce.config[:username], nil); Spaceship.select_team; end` — legacy Portal session login.
- `produce/lib/produce/itunes_connect.rb` → `Spaceship::ConnectAPI.login(Produce.config[:username], nil, use_portal: false, use_tunes: true)` — explicit web (tunes) session, not a token.
- The dev-center half calls `Spaceship.app.create!(...)` → `Spaceship::Portal::PortalClient#create_app!` → `POST account/#{platform_slug(mac)}/identifiers/addAppId.action` (legacy developer.apple.com portal, cookie auth). No `BundleIdCapability` calls at all.
- fastlane's own support matrix (`fastlane/docs/docs/app-store-connect-api.md`): `produce | Apple ID: **Partial** | API Key: **No**` (also `pem | Yes | No`).
**Confidence: high.**

**V5 — The public ASC API has no create-app endpoint; this is Apple's constraint, not fastlane's.**
Evidence: `Spaceship::ConnectAPI::App.create` → `client.post_app(...)` →
`tunes_request_client.post("#{Version::V1}/apps", body)`. With a token,
`Spaceship::ConnectAPI::APIClient#hostname` resolves to
`https://api.appstoreconnect.apple.com/` — where `POST /v1/apps` does not exist.
Apple's own guidance: "Don't use this API to create new apps; instead, create
new apps on the App Store Connect website." Long-standing, still true in 2026
(ASC API is at 4.4, 2026-06-08). **Confidence: high.**

**V6 — Bundle-ID registration + capability enablement IS fully achievable with the API key, via Spaceship ConnectAPI (not via `produce`).**
Evidence: `Spaceship::ConnectAPI::BundleId.create(name:, platform:, identifier:, seed_id:)`
and `#create_capability(capability_type, settings: [])` route through
`provisioning_request_client` → `/v1/bundleIds`, `/v1/bundleIdCapabilities` on
`https://api.appstoreconnect.apple.com/` when a token is set (verified:
`Provisioning::Client < APIClient`; `APIClient#hostname` returns the public API
host iff `@token`). Capability type constants present in
`spaceship/lib/spaceship/connect_api/models/bundle_id_capability.rb` include
exactly what our superset needs: `APP_GROUPS`, `PUSH_NOTIFICATIONS`,
`HEALTHKIT`, `APPLE_ID_AUTH` (SIWA), `ICLOUD`, `IN_APP_PURCHASE`,
`ASSOCIATED_DOMAINS`, `DATA_PROTECTION`, `GAME_CENTER`, `SIRIKIT`,
`GROUP_ACTIVITIES`, `USERNOTIFICATIONS_TIMESENSITIVE`, `CRITICAL_ALERTS`.
Settings constants: `ICLOUD_VERSION`, `DATA_PROTECTION_PERMISSION_LEVEL`,
`APPLE_ID_AUTH_APP_CONSENT`, `GAME_CENTER_SETTING`.
**Caveat:** fastlane docs state **Individual** ASC keys "cannot use Provisioning
endpoints" — `bootstrap_asc` requires a **Team** key (App Manager or Admin).
**Confidence: high.**

**V7 — App Group *identifiers* and iCloud containers cannot be created or associated with the API key.**
Evidence: `produce group` / `associate_group` / `cloud_container` /
`associate_cloud_container` / `merchant` / `associate_merchant` /
`enable_services` / `disable_services` / `available_services` are **CLI
subcommands only** (`produce/lib/produce/commands_generator.rb`) — none is
exposed as a Fastfile action; the only produce action is `create_app_online`
(alias `produce`). They call `Spaceship.app_group.create!` on the legacy portal
(Apple ID). Apple has no public `/v1/appGroups` or `/v1/cloudContainers`
endpoint (open, unanswered developer-forum request 778629). The undocumented
`APP_GROUP_IDENTIFIERS` capability setting exists on the iris endpoint but is
not modelled in spaceship's `Settings` module.
→ **App Group creation is irreducibly manual (or Apple-ID-only).** Since
`group.com.example.myapp` is contract-central (8 entitlements), `bootstrap_asc`
must fail loudly with a documented manual step rather than silently produce a
half-bootstrapped account. **Confidence: high.**

**V8 — Universal Purchase: `produce` handles it only at app-record *creation* time, and only for `ios|osx|tvos`.**
Evidence: `produce/lib/produce/options.rb` — `platform` (`PRODUCE_PLATFORM`,
default `"ios"`, verify_block `%w(ios osx tvos)`) and `platforms`
(`PRODUCE_PLATFORMS`, Array, same whitelist — **no `xros`, no `watchos`**).
`itunes_connect.rb` passes `platforms:` straight into
`Spaceship::ConnectAPI::App.create`. If the record already exists it returns
early: `App '<id>' already exists (<n>), nothing to do` — there is **no
add-a-platform path**. Dev-portal bundle IDs are platform-agnostic in produce
(`mac: platform == "osx"` only picks the portal slug), which matches our
contract's single `com.example.myapp` for iOS+macOS. watchOS rides the iOS
record — correct, nothing to register at ASC level.
**Confidence: high.**

---

### C. `pilot` / `beta`

**V9 — Upload vs distribute is a clean two-call split.** Verified in `pilot/lib/pilot/options.rb`:
| param | env | default | note |
|---|---|---|---|
| `skip_submission` | `PILOT_SKIP_SUBMISSION` | `false` | upload only, no distribution |
| `skip_waiting_for_build_processing` | `PILOT_SKIP_WAITING_FOR_BUILD_PROCESSING` | `false` | **prevents external distribution** |
| `distribute_only` | `PILOT_DISTRIBUTE_ONLY` | `false` | distribute a previously uploaded build (no upload) |
| `app_version` / `build_number` | `PILOT_APP_VERSION` / `PILOT_BUILD_NUMBER` | — | selects the build for `distribute_only` |
| `changelog` | `PILOT_CHANGELOG` | — | "What to Test" |
| `localized_build_info` | `PILOT_LOCALIZED_BUILD_INFO` | — | per-locale whatsNew |
| `localized_app_info` | `PILOT_LOCALIZED_APP_INFO` | — | per-locale beta description/feedback |
| `beta_app_description` / `beta_app_feedback_email` | `PILOT_BETA_APP_DESCRIPTION` / `PILOT_BETA_APP_FEEDBACK` | — | |
| `beta_app_review_info` | `PILOT_BETA_APP_REVIEW_INFO` | — | demo account, contact |
| `distribute_external` | `PILOT_DISTRIBUTE_EXTERNAL` | `false` | requires `groups` |
| `groups` | `PILOT_GROUPS` | — | external group names/IDs |
| `notify_external_testers` | `PILOT_NOTIFY_EXTERNAL_TESTERS` | — | |
| `uses_non_exempt_encryption` | `PILOT_USES_NON_EXEMPT_ENCRYPTION` | `false` | |
| `wait_processing_interval` | `PILOT_WAIT_PROCESSING_INTERVAL` | `30` | seconds |
| `wait_processing_timeout_duration` | `PILOT_WAIT_PROCESSING_TIMEOUT_DURATION` | — | |
| `expire_previous_builds` | `PILOT_EXPIRE_PREVIOUS_BUILDS` | `false` | |
| `reject_build_waiting_for_review` | `PILOT_REJECT_PREVIOUS_BUILD` | `false` | |
| `app_platform` | `PILOT_PLATFORM` | — | verify_block: `ios, appletvos, osx, xros` |
| `pkg` | `PILOT_PKG` | newest `*.pkg` | the `mac_beta` path |
**Confidence: high.**

**V9a — Landmine: `submit_beta_review` shares the env var `PILOT_DISTRIBUTE_EXTERNAL` with `distribute_external`** (`pilot/lib/pilot/options.rb` lines ~218 and ~353, same `env_name`, different defaults `false`/`true`). Never set `PILOT_DISTRIBUTE_EXTERNAL` in `.env`; pass both explicitly in the lane. **Confidence: high.**

**V9b — `contracts.md` §8's `beta` description "gym → pilot, wait, distribute" is one lane doing two pilot calls.** Recommended shape: `pilot(skip_submission: true)` → wait for processing → `pilot(distribute_only: true, distribute_external:, groups:)`. Simpler and equally correct: a single `pilot` call with `distribute_external: true, groups: [...]` (pilot waits for processing internally). Keep the single call as the default; document the split for the "upload now, distribute later" case. **Confidence: high.**

---

### D. `deliver` / `metadata` / `release`

**V10 — Metadata-as-code file names (exact; from `deliver/lib/deliver/upload_metadata.rb` + `setup.rb`, which writes `File.join(path, language, "#{file_key}.txt")`):**
```
fastlane/metadata/
├── copyright.txt
├── primary_category.txt
├── secondary_category.txt
├── primary_first_sub_category.txt
├── primary_second_sub_category.txt
├── secondary_first_sub_category.txt
├── secondary_second_sub_category.txt
├── review_information/
│   ├── first_name.txt   last_name.txt   phone_number.txt
│   ├── email_address.txt  demo_user.txt  demo_password.txt
│   └── notes.txt
├── trade_representative_contact_information/   # <key>.txt, Korea only
└── <locale>/                                    # e.g. en-US/
    ├── name.txt            # LOCALISED_APP_VALUES
    ├── subtitle.txt
    ├── privacy_url.txt
    ├── apple_tv_privacy_policy.txt
    ├── description.txt     # LOCALISED_VERSION_VALUES
    ├── keywords.txt
    ├── release_notes.txt   # → whatsNew
    ├── promotional_text.txt
    ├── support_url.txt
    └── marketing_url.txt
```
Locale dir names must match `Deliver::Languages::ALL_LANGUAGES` (case-insensitive);
`default`, `appleTV`, `iMessage` are reserved special dirs; `android` and `fonts`
are skipped. **Confidence: high.**

**V11 — Screenshots are matched by PIXEL RESOLUTION, not by folder or file name.**
`Deliver::AppScreenshot.calculate_display_type` runs `FastImage.size(path)` and
looks the resolution up in `DEVICE_RESOLUTIONS`. Layout is simply
`fastlane/screenshots/<locale>/<anything>.png` (sorted alphabetically for order).
Only two name-based tiebreakers exist (`CONFLICTING_RESOLUTIONS`):
`2048×2732` → needs `app_ipad_pro_129` or `12.9`+`2nd generation` in the path to
mean the 12.9" slot, else 13"; `3840×2160` → `vision` in the path means Vision
Pro, else Apple TV.
Mapping we care about (constant name → what Apple actually calls it):
| Constant | Real device class | Accepted resolutions |
|---|---|---|
| `APP_IPHONE_67` | **6.9" iPhone** (the required one) | 1320×2868, 1290×2796, 1260×2736 (+landscape) |
| `APP_IPHONE_61` | 6.3" iPhone | 1206×2622, 1179×2556 |
| `APP_IPAD_PRO_3GEN_129` | **13" iPad** (the required one) | 2064×2752, 2048×2732 (+landscape) |
| `APP_DESKTOP` | Mac | 1280×800, 1440×900, 2560×1600, 2880×1800 |
| `APP_WATCH_SERIES_10` | Watch S10 | 416×496 |
| `APP_WATCH_ULTRA` | Watch Ultra | 410×502, 422×514 |
| `APP_APPLE_VISION_PRO` | Vision Pro | 3840×2160 |
Apple's 2026 requirement is one 6.9" iPhone set (1320×2868) plus, if the app
ships on iPad, one 13" iPad set (2064×2752); everything else is auto-scaled.
**Confidence: high** (source) / **med-high** (Apple's exact 2026 minimum set —
corroborated by multiple 2026 ASO references, not an Apple primary source).

**V12 — deliver submit/release flags (from `deliver/lib/deliver/options.rb`):**
`submit_for_review` (`DELIVER_SUBMIT_FOR_REVIEW`, false) ·
`automatic_release` (`DELIVER_AUTOMATIC_RELEASE`, optional) **conflicts with**
`auto_release_date` (`DELIVER_AUTO_RELEASE_DATE`, Integer ms, must be future) ·
`phased_release` (`DELIVER_PHASED_RELEASE`, false) ·
`reset_ratings` (false) · `skip_binary_upload` / `skip_screenshots` /
`skip_metadata` / `skip_app_version_update` (all false) ·
`overwrite_screenshots` (false) · `sync_screenshots` (false — **beta**, also
needs `FASTLANE_ENABLE_BETA_DELIVER_SYNC_SCREENSHOTS=true`) ·
`screenshot_processing_timeout` (3600) ·
`force` (`DELIVER_FORCE`, false) = "Skip verification of HTML preview file" —
**must be `true` in any non-interactive lane** ·
`run_precheck_before_submit` (true) — `Deliver::Runner#precheck_app` returns
early unless set, and only actually runs precheck when `submit_for_review` is
also true · `precheck_include_in_app_purchases` (true — turn OFF when using an
API key, since precheck's IAP rules require Apple ID) ·
`precheck_default_rule_level` (`:warn` from deliver, `:error` from precheck
standalone) · `platform` (`DELIVER_PLATFORM`, default `ios`, whitelist
`ios appletvos tvos xros osx`) · `version_check_wait_retry_limit` (7).
Note the field name is `auto_release_date`, **not** `automatic_release_date`.
**Confidence: high.**

**V13 — Universal Purchase metadata needs two deliver invocations.** One ASC
record, two platforms; version-scoped metadata (description, keywords,
release_notes, promotional_text, support/marketing URL, copyright) and
screenshots are per-platform, so `metadata` runs `deliver(platform: "ios")` and,
when the `mac` component is on, `deliver(platform: "osx")` against separate
`fastlane/metadata/`+`fastlane/screenshots/` trees (`metadata_path` /
`screenshots_path` overrides). App-level values (`name`, `subtitle`,
`privacy_url`, categories) are shared and will simply be re-sent. **Confidence: high.**

---

### E. `snapshot` / `frameit` / `screenshots`

**V14 — `SnapshotHelper.swift` is still required and is now Swift-6 safe.**
Current asset is `SnapshotHelperVersion [1.30]`; the file is annotated
`@MainActor` on the free functions (`setupSnapshot`, `snapshot`) and on
`open class Snapshot: NSObject`, so its `static var app/cacheDirectory/…`
globals do not trip Swift 6 strict-concurrency. No Swift Package alternative
exists. `fastlane snapshot update` refreshes it; `skip_helper_version_check`
(`SNAPSHOT_SKIP_SKIP_HELPER_VERSION_CHECK`, sic) suppresses the staleness check.
Ship it under `UITests/SnapshotHelper.swift` as a vendored, do-not-edit file.
**Confidence: high.**

**V15 — Snapfile matrix + xcodegen wiring.** Relevant options (all
`SNAPSHOT_*`-prefixed unless noted): `devices` (Array), `languages` (Array,
default `['en-US']`), `scheme`, `project` / `workspace`, `test_target_name`,
`testplan`, `only_testing` / `skip_testing`, `output_directory`,
`clear_previous_screenshots` (false), `concurrent_simulators`
(`SNAPSHOT_EXECUTE_CONCURRENT_SIMULATORS`, true), `override_status_bar` (false)
+ `override_status_bar_arguments`, `dark_mode`, `localize_simulator` (false),
`erase_simulator` / `reinstall_app` (false), `headless` (true),
`launch_arguments` (Array), `number_of_retries` (1),
`stop_after_first_error` (`SNAPSHOT_BREAK_ON_FIRST_ERROR`, false),
`disable_slide_to_type`, `result_bundle`, `xcodebuild_formatter`
(auto `xcbeautify` if installed, else `xcpretty`), `xcargs`, `xcconfig`.
For our xcodegen project: snapshot drives the **UITest** target through a
scheme, so root `project.yml` needs a dedicated shared scheme (e.g.
`MyAppScreenshots`) whose `test:` block targets `MyAppUITests` and whose
`build.targets` include `MyApp`. `snapshot(project: "MyApp.xcodeproj", scheme:
"MyAppScreenshots", test_target_name: "MyAppUITests")`. Screenshot-only tests
should be isolated with `only_testing:` or a `.xctestplan` rather than a second
UITest target (contracts §2 has exactly one UITest target and calls it "doubles
as snapshot driver" — that stands).
**Confidence: high** (options) / **med** (the exact scheme name/`only_testing`
split is a W1A/W2B design choice, not a fastlane constraint).

**V16 — snapshot is iOS/tvOS-simulator only. There is no macOS or watchOS screenshot automation in fastlane.** Mac (`APP_DESKTOP`) and Watch screenshots must be produced by hand or by a bespoke XCTest + `XCUIScreen.main.screenshot()` script and dropped into `fastlane/screenshots/<locale>/`. The `screenshots` lane must say so out loud. **Confidence: high.**

**V17 — `frameit` should be OFF by default.** It requires **ImageMagick** installed
on the runner and downloads device frames from `fastlane/frameit-frames`
(originally Facebook design resources, community-maintained; newest devices lag).
`use_platform` defaults to `IOS`. Config is `Framefile.json` +
`keyword.strings`/`title.strings` per locale. Keeping frameit in the `screenshots`
lane behind a `frame: false` lane option keeps the default path
dependency-free and reproducible. **Confidence: med-high.**

---

### F. `gym` / signing / `notarize`

**V18 — gym has NO first-class `-allowProvisioningUpdates` and NO ASC-key plumbing to xcodebuild.**
Evidence: full `ConfigItem` key list of `gym/lib/gym/options.rb` (55 keys) contains
no provisioning/authentication key; `generators/build_command_generator.rb` and
`generators/package_command_generator_xcode7.rb` contain zero occurrences of
`allowProvisioningUpdates`, `authenticationKeyPath`, `authenticationKeyID`, or
`authenticationKeyIssuerID`. The only injection points are
`xcargs` (build phase) and `export_xcargs` (export phase) — the export generator
does `options << config[:export_xcargs] if config[:export_xcargs]` then
`options << config[:xcargs] if config[:xcargs]`.
Therefore both phases need the flags passed manually, and
`-authenticationKeyPath` needs an **absolute** path to a real `.p8` on disk (a
base64 env var must be materialised to a temp file first).
`xcodebuild(1)`: "`-allowProvisioningUpdates` … For automatically signed targets,
xcodebuild will create and update profiles, app IDs, and certificates";
"`-authenticationKeyPath` … Requires `-authenticationKeyID` and
`-authenticationKeyIssuerID`."
**Confidence: high.**

**V19 — gym REJECTS the modern Xcode 15+ export-method names. Our committed `ExportOptions.plist` must use the legacy names.**
Evidence: `gym/lib/gym/options.rb`:
```ruby
av = %w(app-store validation ad-hoc package enterprise development developer-id mac-application)
UI.user_error!("Unsupported export_method '#{value}', must be: #{av}") unless av.include?(value)
```
and `package_command_generator_xcode7.rb`:
```ruby
DEFAULT_EXPORT_METHOD = "app-store"
Gym.config[:export_method] ||= hash[:method] || DEFAULT_EXPORT_METHOD   # read_export_options
hash[:method] = Gym.config[:export_method]                              # config_content — always overwrites
```
`FastlaneCore::Configuration#set` calls `option.verify!(value)` (configuration.rb
:280), so the `||=` assignment from a plist's `method` key **also** runs the
whitelist — passing an `ExportOptions.plist` containing
`<key>method</key><string>app-store-connect</string>` raises
`Unsupported export_method 'app-store-connect'`.
⚠️ **`lang-swift-apple`'s `templates/ExportOptions.plist.tmpl` ships
`method = app-store-connect` and would break gym as written.** Xcode itself
deprecated `app-store`→`app-store-connect` and `ad-hoc`→`release-testing` in
Xcode 15 but still accepts the old spellings with a warning.
→ Use `app-store` (store/TestFlight) and `developer-id` (notarised Mac).
**Confidence: high.**

**V20 — API-key cloud signing DOES work on CI for *distribution*; `match` is not mandatory for our default (App Store) path, but remains the answer for Developer ID and multi-developer determinism.**
Evidence: Xcode 13+ **cloud-managed certificates** are "associated with your
Apple Developer Program membership and managed remotely" — Apple holds the
private key, so an ephemeral runner authenticating with
`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` can
sign without a keychain-resident distribution identity (WWDC21-10204
"Distribute apps in Xcode with cloud signing"). The well-documented failure
mode — *"Your account already has an Apple Development signing certificate for
this machine, but its private key is not installed in your keychain"* — is about
**Development** certificates, which are not cloud-managed and are machine-bound.
Consequence for the template: `beta`/`release` (app-store, distribution) work on
automatic/cloud signing; `notarize`/`mac_beta` outside-store (Developer ID) do
**not** get cloud-managed certs and are the strongest argument for the `match`
opt-in. Keep the ADR-0002 default (`automatic`) and keep `match` opt-in, but
document that Developer ID + notarisation effectively wants `match`
(`type: "developer_id"`, `additional_cert_types: ["developer_id_installer"]`)
or a manually imported `.p12`.
**Confidence: med-high** (Apple's cloud-managed-certificates help page does not
explicitly address CI/private keys; the mechanism is documented in WWDC21).

**V20a — `setup_ci` is required whenever `match` is used on CI.** It creates a
temporary keychain (`fastlane_tmp_keychain`, `timeout` 3600), forces
`match` into `readonly`, and sets log/test-result paths; detects GitHub Actions,
GitLab CI, CircleCI, Bitrise, Jenkins, Azure DevOps, Codemagic, Semaphore,
Bamboo, Travis, Appcircle. **Confidence: high.**

**V21 — `notarize` is notarytool-only, API-key-native, macOS-only.**
Evidence: `fastlane/lib/fastlane/actions/notarize.rb` shells `xcrun notarytool
submit`; there is no `use_notarytool` option any more; the API key is written to
a `Tempfile` and passed as `--key <path> --key-id <id> --issuer <issuer>`;
stapling runs by default unless `skip_stapling`; `asc_provider` maps to
`--team-id` **only on the Apple-ID path**. Options: `package`, `bundle_id`,
`skip_stapling` (false), `print_log` (false), `verbose` (false), `username`,
`asc_provider`, `api_key_path`, `api_key`.
⚠️ fastlane docs: **Individual** ASC API keys "cannot … use `notaryTool`" — the
`notarize` lane needs a **Team** key. **Confidence: high.**

---

### G. `app_store_connect_api_key` — env-var contract

**V22 — fastlane's native env names do NOT match `contracts.md` §8. Ours must be read explicitly in the Fastfile.**
Verbatim from `fastlane/lib/fastlane/actions/app_store_connect_api_key.rb`:
| param | fastlane env_name | type / default |
|---|---|---|
| `key_id` | `APP_STORE_CONNECT_API_KEY_KEY_ID` | String, required |
| `issuer_id` | `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | String, optional (nil ⇒ individual key) |
| `key_filepath` | `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH` | conflicts with `key_content` |
| `key_content` | `APP_STORE_CONNECT_API_KEY_KEY` | **sensitive** |
| `is_key_content_base64` | `APP_STORE_CONNECT_API_KEY_IS_KEY_CONTENT_BASE64` | Bool, `false` |
| `duration` | `APP_STORE_CONNECT_API_KEY_DURATION` | Integer, `500`; **verify_block caps at 1200** |
| `in_house` | `APP_STORE_CONNECT_API_KEY_IN_HOUSE` | Bool, `false` |
| `set_spaceship_token` | `APP_STORE_CONNECT_API_KEY_SET_SPACESHIP_TOKEN` | Bool, `true` |
Run body: `key_content.gsub('\n', "\n")`, then
`Actions.lane_context.set_sensitive(SharedValues::APP_STORE_CONNECT_API_KEY, key)`
and `Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(**key)`.
Both **base64 content** and **path** are supported; base64 is the CI-friendly
form and is what we should default to (empirically verified working on Linux).
Note the docs' JSON-file form uses keys `key_id / issuer_id / key / duration /
in_house` and explicitly **rejects** `key_content` / `key_filepath` inside JSON.
Our three-name contract (`APP_STORE_CONNECT_API_KEY`,
`APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER`) is fine and
arguably clearer than fastlane's stuttering `..._KEY_KEY_ID` — but it only works
if the Fastfile reads them explicitly. It also cleanly matches
`altool`/`notarytool` conventions and the existing `lang-swift-apple` docs.
**Keep our names; pass them explicitly; document the mapping.**
**Confidence: high.**

**V22a — Add `APP_STORE_CONNECT_API_KEY_P8_PATH` handling as the local/1Password
alternative already named in contracts §8, and set `in_house: false`,
`duration: 1200` (max) so long `deliver` runs don't need mid-flight refresh
(spaceship refreshes anyway via `@token.refresh!`).** **Confidence: high.**

---

### H. `status` lane (Spaceship)

**V23 — A rich, API-key-only status dump is fully feasible.** All of these are
public-API/token paths on `Spaceship::ConnectAPI`:
- `App.find(bundle_id)` → id, name, sku, primary_locale, bundle_id
- `app.get_builds(filter: { … })` / `Build.all(app_id:, version:, build_number:, platform:, processing_states: "PROCESSING,FAILED,INVALID,VALID", sort: "-uploadedDate", limit: 30)` with `Build::ProcessingState = { PROCESSING, FAILED, INVALID, VALID }`, plus `version`, `uploaded_date`, `expired`, `min_os_version`, `uses_non_exempt_encryption`
- `app.get_edit_app_store_version` / `get_live_app_store_version` / `get_in_review_app_store_version` / `get_pending_release_app_store_version`
- `app.get_review_submissions` / `get_ready_review_submission`
- `app.get_beta_groups`, `app.get_beta_testers`, `app.get_beta_feedback`
- `BundleId.all(filter: { identifier: … })` + `bundle_id.get_capabilities` — lets `status` also *verify* the bootstrap (all 8 IDs present, right capabilities on each), which is more valuable than a plain dump.
- `Spaceship::ConnectAPI::Profile` / `Certificate` for signing state (Team key).
`app_store_build_number` and `latest_testflight_build_number` are ready-made
actions for the "highest build number" question.
**Confidence: high.**

---

### I. Lane list

**V24 — The frozen lane list survives, with two amendments.**
- `bootstrap_asc` **cannot** do "app record" with the API key (V4/V5). It must
  split: create/verify bundle IDs + capabilities via Spaceship (API key, works),
  and *check* for the app record + App Group, failing with an actionable message
  pointing at `docs/asc-setup.md` when absent. An opt-in Apple-ID path
  (`FASTLANE_USER` + `FASTLANE_SESSION` from `fastlane spaceauth`) can call
  `produce` for the record — but must be explicitly enabled, never the default.
- `certs` should also cover the `developer_id` types for the notarise path when
  signing=match.
No lane needs renaming, no lane needs adding, no lane needs deleting.
**Confidence: high.**

**V25 — No fastlane plugins are required for any of our lanes.** produce, gym,
pilot, deliver, precheck, snapshot, frameit, match, notarize,
app_store_connect_api_key, setup_ci, app_store_build_number,
latest_testflight_build_number are all core. `Pluginfile` should not exist
(its absence is itself a signal). **Confidence: high.**

**V26 — Xcode Cloud and fastlane coexist without conflict.** Xcode Cloud's
`ci_scripts/ci_post_clone.sh|ci_pre_xcodebuild.sh|ci_post_xcodebuild.sh` run on
Apple's runners with Xcode + brew; archive/TestFlight/App Store distribution are
native Xcode Cloud actions requiring **no** API key. The two CI choices are
disjoint consumers of the same `Config/Versions.xcconfig` write step
(ADR-0007). The only rule: Xcode Cloud must not also run the `beta` lane, or
build numbers double-increment. **Confidence: high.**

**V27 — Runner facts for `github_actions`:** `macos-26` went GA 2026-02-26;
`macos-latest` began resolving to `macos-26` from 2026-06-15; default Xcode on
the image is **26.6** (set 2026-07-21); arm64 labels `macos-26`, `macos-26-xlarge`.
Apple requires uploads to be built with the **iOS 26 SDK or later since
2026-04-28**. Pin explicitly (`runs-on: macos-26` + `maxim-lobanov/setup-xcode`)
rather than relying on `macos-latest`. **Confidence: high.**

---

## Spec deltas

### Δ1 — `specs/_build/contracts.md` §8, replace the whole section

> ## 8. Fastlane surface (ADR-0002; R1 refines lane internals, NOT lane names)
>
> Lane names are API: `bootstrap_asc`, `beta`, `screenshots`, `metadata`,
> `release`, `certs`, `status`, `mac_beta`, `notarize`. Make targets delegate
> 1:1: `make testflight|screenshots|metadata-push|release|asc-status|asc-bootstrap|notarize-mac`.
>
> **Auth.** `app_store_connect_api_key` invoked explicitly from `before_all`
> with our own env names: `APP_STORE_CONNECT_API_KEY` (base64 `.p8`) **or**
> `APP_STORE_CONNECT_API_KEY_P8_PATH`, plus `APP_STORE_CONNECT_API_KEY_ID` and
> `APP_STORE_CONNECT_API_ISSUER`. (fastlane's own `APP_STORE_CONNECT_API_KEY_KEY_ID`
> / `_ISSUER_ID` / `_KEY` env names are deliberately NOT used; the Fastfile
> reads ours and passes them as parameters.) `duration: 1200`, `in_house: false`.
> The key MUST be a **Team** key — Individual keys cannot use provisioning
> endpoints or notarytool.
>
> **`bootstrap_asc` is capability-limited by Apple, not by us.** The App Store
> Connect API has no create-app endpoint and `produce` authenticates only with
> an Apple ID + 2FA session (both its Dev-Portal and its ASC half). Therefore:
> `bootstrap_asc` registers/verifies **all bundle IDs and their capabilities**
> through `Spaceship::ConnectAPI::BundleId` + `BundleIdCapability` with the API
> key (this works), and **checks** for (a) the ASC app record and (b) the App
> Group identifier, failing with an actionable pointer to `docs/asc-setup.md`
> when either is missing. App-record creation, App Group creation, and iCloud
> container creation are the documented manual residue. An opt-in Apple-ID path
> (`FASTLANE_USER` + `FASTLANE_SESSION` from `fastlane spaceauth`) may call
> `produce` / `produce group` / `produce associate_group`; it is never the
> default and never runs unattended.
>
> **Signing.** Default automatic/cloud: gym has no native support, so the lane
> passes `-allowProvisioningUpdates -authenticationKeyPath <abs> -authenticationKeyID
> <id> -authenticationKeyIssuerID <issuer>` through BOTH `xcargs:` and
> `export_xcargs:`, materialising the base64 key to a temp `.p8` first.
> `match` is an onboarding opt-in and is the recommended path for Developer ID /
> notarised Mac builds; when `match` is on, every CI lane calls `setup_ci`.
> `ExportOptions.plist` MUST use the legacy method spellings (`app-store`,
> `developer-id`) — gym's `export_method` whitelist rejects
> `app-store-connect`/`release-testing`.
>
> **Ruby.** `Gemfile` + `Gemfile.lock` committed, `fastlane` pinned to
> `2.237.0`, `.ruby-version` = `3.4.x`. No `Pluginfile` — every lane uses core
> actions only. All Linux jobs export `LC_ALL=C.UTF-8 LANG=C.UTF-8`.
> API-only lanes (`metadata`, `status`, `bootstrap_asc`, `pilot` distribute)
> run on Linux; `beta`, `mac_beta`, `screenshots`, `notarize`, and `certs`
> (keychain import) guard with an explicit `FastlaneCore::Helper.mac?` check —
> gym does **not** fail closed on its own.

### Δ2 — `docs/adr/0002-fastlane-release-automation.md`, Context paragraph

Replace:
> `produce` creates app records and registers bundle IDs/capabilities (the raw
> REST API cannot create app records)

with:
> `produce` creates app records and registers bundle IDs/capabilities — but only
> with an Apple ID + 2FA session, because Apple's REST API has no create-app
> endpoint and `produce`'s Dev-Portal half still uses the legacy portal
> (`addAppId.action`). The API-key-compatible half of that surface is
> `Spaceship::ConnectAPI::BundleId` / `BundleIdCapability`, which fastlane
> exposes as a library even though no lane action wraps it (see R1 §B).

### Δ3 — `docs/adr/0002`, Decision paragraph

Replace:
> Default signing stays automatic/cloud (API key + `-allowProvisioningUpdates`)

with:
> Default signing stays automatic/cloud (API key + `-allowProvisioningUpdates`),
> which works because Xcode 13+ **cloud-managed distribution certificates** keep
> the private key with Apple; note the same trick does not exist for Development
> or Developer ID certificates, so the notarised-Mac path is the strongest case
> for the `match` opt-in. gym has no native flag for this — the lane threads the
> flags through `xcargs:`/`export_xcargs:`.

### Δ4 — `docs/adr/0002`, Consequences, add two bullets

> - `fastlane` is pinned to 2.237.0 and `.ruby-version` to 3.4.x, matching the
>   only Ruby line fastlane tests against Xcode 26.x. macOS system Ruby is
>   unusable; brew/rbenv/mise required.
> - `bootstrap_asc` is partial by construction. App record, App Group, and
>   iCloud container creation are documented manual steps in `docs/asc-setup.md`
>   with an opt-in Apple-ID escape hatch.

### Δ5 — `contracts.md` §9, `ops:` block, add one field

> ```yaml
> ops:
>   ci_system: xcode_cloud     # xcode_cloud | github_actions | none
>   signing: automatic         # automatic | match
>   frameit: false             # frameit needs ImageMagick + community frames
>   autonomy: continue-until-blocked
>   squash_history: false
> ```

### Δ6 — Fastfile skeleton (normative structure for W2B)

```ruby
# fastlane/Fastfile
fastlane_version "2.237.0"
opt_out_usage
skip_docs

APP_ID       = "com.example.myapp"
APP_GROUP_ID = "group.com.example.myapp"
EXTENSION_IDS = {                            # bundle id => [capability types]
  "com.example.myapp"                          => %w[APP_GROUPS PUSH_NOTIFICATIONS],
  "com.example.myapp.watch"                    => %w[APP_GROUPS],
  "com.example.myapp.watch.complications"      => %w[APP_GROUPS],
  "com.example.myapp.homewidget"               => %w[APP_GROUPS],
  "com.example.myapp.liveactivity"             => %w[APP_GROUPS],
  "com.example.myapp.notificationservice"      => %w[APP_GROUPS],
  "com.example.myapp.macwidget"                => %w[APP_GROUPS],
}.freeze

before_all do |lane, options|
  ENV["FASTLANE_SKIP_UPDATE_CHECK"] = "1"
  ENV["FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT"] ||= "120"
  load_asc_api_key unless lane == :nothing          # private lane, below
end

error do |lane, exception, options|
  UI.error("lane #{lane} failed: #{exception.message}")
  # no notifier by default; W2E may add one
end

private_lane :load_asc_api_key do
  next if ENV["APP_STORE_CONNECT_API_KEY_ID"].to_s.empty?
  app_store_connect_api_key(
    key_id:                ENV.fetch("APP_STORE_CONNECT_API_KEY_ID"),
    issuer_id:             ENV.fetch("APP_STORE_CONNECT_API_ISSUER"),
    key_content:           ENV["APP_STORE_CONNECT_API_KEY"],
    key_filepath:          ENV["APP_STORE_CONNECT_API_KEY_P8_PATH"],
    is_key_content_base64: !ENV["APP_STORE_CONNECT_API_KEY"].to_s.empty?,
    duration:              1200,
    in_house:              false,
  )
end

private_lane :require_macos do
  UI.user_error!("This lane requires macOS + Xcode.") unless FastlaneCore::Helper.mac?
end

private_lane :signing_xcargs do                     # returns String
  # materialise base64 .p8 -> temp file, return the four xcodebuild flags
end

platform :ios do
  lane :bootstrap_asc do ... end       # Spaceship BundleId/Capability + preflight checks
  lane :beta        do require_macos; ... gym → pilot ... end
  lane :screenshots do require_macos; snapshot; frameit if options[:frame] end
  lane :metadata    do deliver(skip_binary_upload: true, skip_metadata: false, force: true, ...) end
  lane :release     do precheck; deliver(submit_for_review: true, phased_release: true, force: true, ...) end
  lane :certs       do match(...) end
  lane :status      do ... end         # Spaceship dump, Linux-clean
end

platform :mac do
  lane :beta     do require_macos; ... end   # invoked as `mac_beta` via a top-level alias
  lane :notarize do require_macos; gym(export_method: "developer-id"); notarize(...) end
  lane :metadata do deliver(platform: "osx", ...) end
end

lane :mac_beta do Fastlane::LaneManager.cruise_lane("mac", "beta") end  # or: `fastlane mac beta`
```
Note: `contracts.md` freezes the **name** `mac_beta`. Either keep a
top-level `lane :mac_beta` that switches into `platform :mac`, or drop the
`platform :mac` block entirely and define `mac_beta`/`notarize` inside
`platform :ios`. The second is simpler and is the recommended reading of the
frozen list — flagging it for Fable to decide at the gate.

---

## Capability audit

**Native capabilities our current design under-uses**

1. **`deliver`'s resolution-based screenshot routing.** We were about to invent a
   device-named directory scheme. deliver ignores names entirely — one flat
   `<locale>/` folder per platform is the whole contract. Also unused:
   `default/` (locale fallback), `individual_metadata_items` (per-field upload
   for pinpointing which field Apple rejected), `app_previews_path` +
   `preview_frame_time_code` (App Preview videos), `overwrite_screenshots` /
   `sync_screenshots`, `screenshot_processing_timeout`.
2. **`deliver`'s `platform:` parameter** does the entire Universal-Purchase
   metadata story (`ios` + `osx` against the one record). No second app record,
   no bespoke logic.
3. **`precheck` as a standalone lane action** — we only wire it via
   `run_precheck_before_submit`. Running `precheck` directly in `release` (with
   `include_in_app_purchases: false` when API-key-authed) gives a fail-fast gate
   before any upload.
4. **`gym`'s `generate_appstore_info`** — produces the `AppStoreInfo.plist`
   Transporter needs, which is exactly the missing piece for a
   build-on-mac/upload-from-linux split. Currently unused.
5. **`gym`'s `result_bundle` / `result_bundle_path` / `xcodebuild_formatter`
   (`xcbeautify`) / `build_timing_summary` / `cloned_source_packages_path` /
   `package_cache_path` / `skip_package_repository_fetches`** — free CI caching
   and diagnostics we're not asking for.
6. **`setup_ci`** — we never mention it. It is the *native* answer to "temporary
   keychain on CI", which teams routinely hand-roll with
   `security create-keychain`.
7. **`app_store_build_number` / `latest_testflight_build_number`** — native
   actions for "what's the highest build number on ASC". ADR-0007 uses
   `git rev-list --count HEAD` (correct, monotonic), but the `status` lane should
   *report* both so a divergence is visible instead of discovered at upload time.
8. **`Spaceship::ConnectAPI::BundleId#get_capabilities`** — turns `status` from a
   dump into a *verifier* of the §2 bundle-ID registry. This is the single
   highest-value unused capability in the whole surface.
9. **`pilot`'s `localized_build_info` / `localized_app_info`** — per-locale
   "What to Test" and beta descriptions, free once String Catalogs exist.
10. **`pilot`'s `expire_previous_builds` and `reject_build_waiting_for_review`** —
    native TestFlight hygiene we'd otherwise do by hand in the ASC UI.
11. **`snapshot`'s `override_status_bar` (9:41, full bars), `dark_mode`,
    `localize_simulator`, `testplan`, `only_testing`, `concurrent_simulators`** —
    the whole "App-Store-grade screenshots" story is config, not code.
12. **fastlane's `Appfile`** (`app_identifier`, `apple_id`, `team_id`,
    `itc_team_id`, `apple_dev_portal_id`, `itunes_connect_id`) is the native
    place for identity defaults; contracts §1 currently implies every lane
    repeats them. One `Appfile` with the four rename tokens is the tool-native
    move.
13. **`fastlane_version` / `min_fastlane_version` in the Fastfile** — native
    guard against a Gemfile.lock/Fastfile skew.
14. **`.env` / `.env.default` / `--env <name>` (dotenv)** — fastlane natively
    loads `fastlane/.env*`. We plan a `.env.example`; wiring it to fastlane's
    dotenv rather than a bespoke loader is free.

**Things we plan to hand-roll that a tool already does**

- ❌ *Bespoke ASC REST/JWT scripts* — already reversed by ADR-0002. Confirmed
  correct: `app_store_connect_api_key` + Spaceship covers 100% of the API-key
  surface, verified running on Linux.
- ⚠️ **`ExportOptions.plist` as a committed file is arguably redundant.** gym
  *generates* the export options plist every run and unconditionally overwrites
  `method`, `uploadSymbols`, `uploadBitcode`, `teamID`, `signingStyle`,
  `installerSigningCertificate`. Passing `export_options: { … }` as a Ruby hash
  in the lane is the tool-native form and removes a file that can silently
  disagree with the lane. Recommend: keep `ExportOptions.plist` only if a
  non-fastlane `xcodebuild -exportArchive` path is also supported (it is — the
  `verify-macos` matrix and manual fallback), and make W2B assert the two agree.
- ⚠️ **Do not hand-roll "wait for build processing"** — `pilot` does it
  (`wait_processing_interval`, `wait_processing_timeout_duration`), and
  `Build::ProcessingState` is already modelled.
- ⚠️ **Do not hand-roll a temp keychain** — `setup_ci` (V20a).
- ⚠️ **Do not hand-roll changelog injection** — `pilot(changelog:)` and
  `deliver`'s `release_notes.txt` are the two native seams; a
  `fastlane/metadata/<locale>/release_notes.txt` read by the `beta` lane keeps
  one source of truth for both.
- ✅ **`Spaceship::ConnectAPI::BundleId` in `bootstrap_asc` is NOT hand-rolling** —
  it is fastlane's own library, just not wrapped in a lane action. Using it is
  the capability-maximising choice; writing raw JWT + Faraday would not be.
- ❗ **`produce group` / `associate_group` will be tempting to shell out to.**
  Don't: it needs an Apple ID session, so `sh("bundle exec fastlane produce
  associate_group …")` inside an API-key lane will hang on a 2FA prompt in CI.
  Fail with a message instead.

---

## Sources

| # | Source | URL | Retrieved / dated |
|---|---|---|---|
| 1 | RubyGems fastlane version index | `https://rubygems.org/api/v1/versions/fastlane.json` | 2026-08-02 (2.237.0 = 2026-07-05) |
| 2 | `fastlane.gemspec` (master) | https://raw.githubusercontent.com/fastlane/fastlane/master/fastlane.gemspec | 2026-08-02 |
| 3 | fastlane CI matrix `.github/workflows/ci.yml` | https://raw.githubusercontent.com/fastlane/fastlane/master/.github/workflows/ci.yml | 2026-08-02 |
| 4 | Installing fastlane (docs source) | https://raw.githubusercontent.com/fastlane/docs/master/docs/includes/installing-fastlane.md | 2026-08-02 |
| 5 | Using App Store Connect API (support matrix) | https://raw.githubusercontent.com/fastlane/docs/master/docs/app-store-connect-api.md · https://docs.fastlane.tools/app-store-connect-api/ | 2026-08-02 |
| 6 | `app_store_connect_api_key.rb` | https://raw.githubusercontent.com/fastlane/fastlane/master/fastlane/lib/fastlane/actions/app_store_connect_api_key.rb | 2026-08-02 |
| 7 | `produce/lib/produce/{options,developer_center,itunes_connect,service,group,commands_generator}.rb` | https://raw.githubusercontent.com/fastlane/fastlane/master/produce/lib/produce/ | 2026-08-02 |
| 8 | `spaceship/.../connect_api/models/{app,bundle_id,bundle_id_capability,build}.rb`, `provisioning/{client,provisioning}.rb`, `tunes/{client,tunes}.rb`, `api_client.rb`, `portal/{app,portal_client}.rb` | https://raw.githubusercontent.com/fastlane/fastlane/master/spaceship/lib/spaceship/ | 2026-08-02 |
| 9 | `gym/lib/gym/options.rb`, `generators/{build_command_generator,package_command_generator_xcode7}.rb` | https://raw.githubusercontent.com/fastlane/fastlane/master/gym/lib/gym/ | 2026-08-02 |
| 10 | `fastlane_core/.../configuration/configuration.rb` (`set` → `verify!`) | https://raw.githubusercontent.com/fastlane/fastlane/master/fastlane_core/lib/fastlane_core/configuration/configuration.rb | 2026-08-02 |
| 11 | `deliver/lib/deliver/{options,upload_metadata,app_screenshot,setup,loader,runner}.rb` | https://raw.githubusercontent.com/fastlane/fastlane/master/deliver/lib/deliver/ | 2026-08-02 |
| 12 | `pilot/lib/pilot/options.rb` · pilot docs | https://raw.githubusercontent.com/fastlane/fastlane/master/pilot/lib/pilot/options.rb · https://docs.fastlane.tools/actions/pilot/ | 2026-08-02 |
| 13 | `snapshot/lib/snapshot/options.rb` · `snapshot/lib/assets/SnapshotHelper.swift` (v1.30) · snapshot docs | https://raw.githubusercontent.com/fastlane/fastlane/master/snapshot/ · https://docs.fastlane.tools/actions/snapshot/ | 2026-08-02 |
| 14 | frameit docs | https://docs.fastlane.tools/actions/frameit/ | 2026-08-02 |
| 15 | `notarize.rb` · notarize docs | https://raw.githubusercontent.com/fastlane/fastlane/master/fastlane/lib/fastlane/actions/notarize.rb · https://docs.fastlane.tools/actions/notarize/ | 2026-08-02 |
| 16 | match docs · setup_ci docs | https://docs.fastlane.tools/actions/match/ · https://docs.fastlane.tools/actions/setup_ci/ | 2026-08-02 |
| 17 | `xcodebuild(1)` man page (flags for provisioning/auth/export) | https://keith.github.io/xcode-man-pages/xcodebuild.1.html | 2026-08-02 |
| 18 | Apple — Cloud-managed certificates | https://www.developer.apple.com/help/account/certificates/cloud-managed-certificates | 2026-08-02 |
| 19 | Apple — "Distribute apps in Xcode with cloud signing" (WWDC21-10204) | https://developer.apple.com/videos/play/wwdc2021/10204/ | session 2021, still the canonical description |
| 20 | Apple — upcoming SDK minimum requirements (iOS 26 SDK required from 2026-04-28) | https://developer.apple.com/news/?id=ueeok6yw | 2026 |
| 21 | Apple — App Store Connect API release notes (4.4, 2026-06-08) | https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-release-notes | 2026-08-02 |
| 22 | Apple Developer Forums — "Why is there no App Store Connect API endpoint to create new apps?" (746582); "Possible to create App Groups with the ASC API?" (778629, unanswered) | https://developer.apple.com/forums/thread/746582 · /778629 | 2026-08-02 |
| 23 | GitHub Changelog — macos-26 GA (2026-02-26); macos-latest → macos-26 (Issue 14167); default Xcode 26.6 (Issue 13519) | https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/ · https://github.com/actions/runner-images | 2026-08-02 |
| 24 | Ruby 4.0.0 release (2025-12-25); Ruby 3.4.10 (2026-06-30); Ruby 4.0.6 (2026-07-14) | https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/ · https://www.ruby-lang.org/en/downloads/ | 2026-08-02 |
| 25 | **Empirical**: `bundle install` + `bundle exec fastlane` of fastlane 2.237.0 on Ubuntu 24.04 / Ruby 3.3.6 / Bundler 4.0.17, incl. `app_store_connect_api_key` with a locally generated P-256 `.p8` (base64) → JWT minted, `Spaceship::ConnectAPI.token` set | this session | 2026-08-02 |
