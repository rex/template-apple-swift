# Lane semantics

Deep detail behind the lane map in `SKILL.md`. The narrative walkthrough is
`docs/release-automation.md` §3 — this file is the part that is easy to get
subtly wrong, distilled from reading fastlane's own source.

## `beta` — TestFlight

Shape: icon preflight → export-options assertion → `gym` → `pilot`.

`pilot`'s upload and distribute halves are separable, which matters when a
build should go up now and out later:

| Parameter | Default | Effect |
|---|---|---|
| `skip_submission` | `false` | Upload only, no distribution |
| `skip_waiting_for_build_processing` | `false` | Setting it **prevents external distribution** |
| `distribute_only` | `false` | Distribute a build already uploaded (needs `app_version` / `build_number`) |
| `distribute_external` | `false` | Requires `groups` |
| `groups` | — | External group names or IDs |
| `changelog` | — | TestFlight "What to Test" |
| `expire_previous_builds` | `false` | |
| `wait_processing_interval` | `30` s | |

The default path is a **single** `pilot` call that uploads, waits for
processing and distributes — pilot handles the wait internally. The two-call
split (`skip_submission: true`, then `distribute_only: true`) exists for
"upload now, distribute after QA".

Internal testers get a build with no review. External distribution needs
`groups:` and triggers beta review.

**The landmine:** `submit_beta_review` and `distribute_external` share the env
var `PILOT_DISTRIBUTE_EXTERNAL` with *opposite* defaults. Setting it in `.env`
silently changes a behaviour you did not touch. Pass both as lane parameters.

Usage:

```bash
make testflight
bundle exec fastlane beta changelog:'Fixes the widget refresh'
bundle exec fastlane beta external:true groups:'Friends & Family'
```

## `metadata` and `release` — deliver

`fastlane/metadata/` is the source of truth and App Store Connect is a cache
of it. The exact file names are deliver's API, not a convention — the full
schema is documented at the top of `fastlane/Deliverfile`. Locale directory
names must match deliver's language list; `default`, `appleTV` and `iMessage`
are reserved.

`fastlane/metadata/en-US/release_notes.txt` is deliberately shared: `beta`
reads it as TestFlight's "What to Test", and `metadata`/`release` upload it as
the store listing's release notes.

Flags worth knowing before changing a lane:

- `force: true` is mandatory in any non-interactive run — it skips the HTML
  preview confirmation, not any validation.
- `precheck_include_in_app_purchases` must be **off** under an API key:
  precheck's IAP rules need an Apple ID session.
- `run_precheck_before_submit` only actually runs precheck when
  `submit_for_review` is also true. The `release` lane therefore runs
  `precheck` explicitly, at `:error` level, as a fail-fast gate before
  anything uploads.
- `automatic_release` conflicts with `auto_release_date` (note the name — it
  is not `automatic_release_date`). This repo ships phased release **on** and
  automatic release **off**.

**Universal Purchase needs two `deliver` invocations.** One App Store Connect
record, two platforms: version-scoped metadata (description, keywords, release
notes, promotional text, support/marketing URLs, copyright) and screenshots
are per-platform. So `metadata` runs `platform: "ios"` and, when the `mac`
component is on, `platform: "osx"` against separate metadata and screenshot
trees. App-level values (name, subtitle, privacy URL, categories) are shared
and simply get re-sent.

## `screenshots` — snapshot

**Screenshots are matched by pixel resolution, not by folder or file name.**
deliver reads each PNG's dimensions and looks them up in a resolution table.
Layout is flat: `fastlane/screenshots/<locale>/<anything>.png`, sorted
alphabetically for ordering.

| Resolution | Slot |
|---|---|
| 1320×2868 · 1290×2796 · 1260×2736 | 6.9" iPhone — the required set |
| 1206×2622 · 1179×2556 | 6.3" iPhone |
| 2064×2752 · 2048×2732 | 13" iPad — required if the app ships on iPad |
| 1280×800 · 1440×900 · 2560×1600 · 2880×1800 | Mac |
| 416×496 | Watch Series 10 |

Two name-based tiebreakers exist: `2048×2732` needs `12.9` or
`app_ipad_pro_129` in the path to mean the 12.9" slot rather than 13", and
`3840×2160` needs `vision` in the path to mean Vision Pro rather than Apple
TV.

`SnapshotHelper.swift` is vendored into `UITests/` as a do-not-edit file
(v1.30, `@MainActor`, Swift-6 safe). There is no Swift Package alternative.
`fastlane snapshot update` refreshes it. It drives the `MyAppScreenshots`
scheme against the `MyAppUITests` target.

**snapshot is iOS-simulator only.** There is no macOS and no watchOS
screenshot automation in fastlane, at all. Mac and Watch screenshots are
produced by hand — or by a bespoke `XCUIScreen.main.screenshot()` test — and
dropped into `fastlane/screenshots/<locale>/`.

`frameit` is off by default (`ops.frameit: false`): it needs ImageMagick on
the runner plus community-maintained device frames that lag new hardware.
Keeping it off keeps `make screenshots` dependency-free and reproducible.

## `bootstrap_asc` and `status`

`bootstrap_asc` registers every bundle ID and enables its capabilities through
Spaceship's ConnectAPI with the API key — that part genuinely works. It
derives the ID list from the directories present in the repo, so a pruned app
never registers identifiers it does not ship.

What it **checks and fails on** rather than creating: the App Store Connect
app record, and the App Group identifier. Neither has a public API endpoint;
`produce` authenticates only with an Apple ID plus a 2FA session, on both its
Dev-Portal and its ASC half. That is Apple's limit, not fastlane's.
`docs/asc-setup.md` is the manual residue, and the lane's failure message
points there.

Run it once per app, and again after enabling a component:

```bash
make asc-bootstrap
bundle exec fastlane bootstrap_asc dry_run:true   # plan first
```

`status` is the read-only twin: same registry, plus app record, versions
(live / edit / in review / pending), recent builds with processing state,
TestFlight groups, and the three build numbers (`git rev-list --count HEAD`,
TestFlight latest, App Store live) side by side, so divergence is visible
before an upload rejects.

## Mac lanes

`mac_beta` (Mac App Store TestFlight) and `notarize` (Developer ID +
notarytool) both refuse when the `mac` component is absent, and both guard on
macOS explicitly. Developer ID certificates are **not** cloud-managed, which
is the strongest single argument for turning `match` on — see
`references/keys.md`.
