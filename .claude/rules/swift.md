# Swift / Apple rules (hard stops)

> Loaded as a project-level rule from `.claude/rules/`. Applies to every
> session in this repo. Depth lives in `docs/template-guide.md` and in the
> `lang-swift-apple` skill; this file is the short list you must not violate.

## Concurrency — explicit isolation, always

- **Every type carries `@MainActor` or `nonisolated` explicitly.** Nothing in
  this repo relies on `SWIFT_DEFAULT_ACTOR_ISOLATION`, so the sources compile
  identically under Xcode 26's new-project default (`MainActor`) and the
  legacy default (`nonisolated`). Adding a type without an isolation
  annotation is a review failure, not a style nit.
- These MUST be `nonisolated`: every `TimelineProvider` conformance, the
  `UNNotificationServiceExtension` subclass, the `WCSessionDelegate`
  conformance, everything in `Shared/Sync/WidgetSync.swift`,
  `SessionActivityAttributes`, and `Shared/Theme/Theme.swift`. They are read
  from extension processes and from non-main-actor callbacks.
- `SWIFT_VERSION` is `6.0` — a **language mode**, not a toolchain version.
  Strict concurrency is complete; `@unchecked Sendable` needs a comment
  justifying it, and `nonisolated(unsafe)` needs an ADR.
- Static members on `AppIntent` / `AppShortcutsProvider` metadata are
  `static let`. Swift 6 rejects mutable stored static vars.
- App Intents types (`AppIntent` conformers, `AppShortcutsProvider`) are
  `@MainActor`, **never** `nonisolated`: a type-level `nonisolated`
  distributes onto `@Parameter`/`@Dependency`, which are mutable stored
  properties — "'nonisolated' cannot be applied to mutable stored
  properties". Gate-checked.
- Those conformances can also never be **isolated**: `AppIntent` and
  `AppShortcutsProvider` inherit `Sendable`, so their metatypes are
  `SendableMetatype` and SE-0470 forbids (and never infers) an isolated
  conformance — "conformance crosses into main actor-isolated code". So every
  synchronous witness is explicitly `nonisolated`: a hand-written
  `nonisolated init() {}` (the synthesized init would be isolated),
  `nonisolated static let` metadata, and a `nonisolated static var
  appShortcuts` getter. `perform()` is the only isolated member the
  conformance tolerates, because that requirement is `async`.
  `MyApp/Intents/CheckpointIntents.swift` is the canonical shape.

## Project structure — generated, not hand-edited

- `project.yml` + `xcodegen/components/*.yml` are the source of truth.
  **`MyApp.xcodeproj` is a build artifact**: never open it to change a
  setting, never commit it. Run `make regenerate` after any YAML edit.
- Every `Info.plist` and `.entitlements` is generated from the `info:` /
  `entitlements:` blocks in YAML and is gitignored. Editing one on disk edits
  a file the next `xcodegen` run deletes. `PrivacyInfo.xcprivacy` is the one
  hand-authored plist, and every bundle needs its own.
- Included specs merge **additively and arrays concatenate with no
  deduplication**. Exactly one file may own any given dependency edge, source
  entry or scheme entry, and the root spec must not restate what a component
  contributes.
- Every `include:` entry uses the object form with `relativePaths: false`.
  The string form re-roots every path in the included file.

## SwiftUI + resources

- `@Observable` + `@State`/`@Environment` only. `ObservableObject`,
  `@Published`, `@StateObject` and `@EnvironmentObject` are forbidden and
  gate-checked.
- All design values come from `Theme` (`Theme.color.*`, `Theme.font.*`,
  `Theme.spacing.*`, `Theme.radius.*`). No hex literals, no magic numbers, no
  ad-hoc `.font(.system(size:))` in a view.
- User-facing strings live in the String Catalog (`.xcstrings`). A literal
  string in a view is a localization bug.
- Business logic lives in stores/services; views stay declarative.
  `CheckpointStore` is the ONLY mutation path, and every mutation writes
  through `WidgetSync`.

## The gotcha table

Each of these has cost someone a day. Detail: `docs/template-guide.md`.

| # | Rule |
|---|---|
| 1 | The watch app MUST be a `dependencies:` entry on the iOS app, or it is silently absent from the `.ipa` with no build error. |
| 2 | `MyAppWatch` needs `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` = the iOS bundle ID, or pairing breaks at install time. |
| 3 | The watch app needs the App Group entitlement even before it reads the group — without it `exportArchive` fails with exit 70. |
| 4 | `NSSupportsLiveActivities` goes in the **host** app's Info.plist, never the Live Activity extension's. |
| 5 | Every widget and complication view MUST call `.containerBackground(_:for: .widget)`, or the system renders an "adopt containerBackground" placeholder instead of your widget. |
| 6 | `WidgetFamily.accessoryCorner` is watchOS-only; listing it in an iOS/macOS `supportedFamilies` array fails to compile on the Xcode 26 SDK. |
| 7 | Guard ActivityKit with `#if os(iOS)`, never `#if canImport(ActivityKit)` — the module imports on macOS but its types are unavailable. |
| 8 | An extension's bundle ID is its immediate host's ID plus **exactly one** dot-segment. Two segments or a sibling prefix is an ITMS-90347 rejection at upload. |
| 9 | Silent pushes are rate-budgeted by iOS and are dropped without warning; user-visible payloads with `mutable-content: 1` handled by the NSE are the reliable path. |
| 10 | `WCSession` payloads are capped around 65 KB and `updateApplicationContext` keeps only the latest value — send a small summary, never a history. |
| 11 | `.xcconfig` is the LOWEST layer of Xcode's build-setting precedence. `DEVELOPMENT_TEAM`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `Config/*.xcconfig` and nowhere else; the same key in `project.yml` silently wins and the xcconfig looks broken. |
| 12 | `Activity`'s async methods (`update`, `end`) hop to the global executor. Call them from **detached** tasks that fetch the activity inside their own region; carrying an `Activity` reference out of the main-actor region is a "sending … risks causing data races" compile error. Reading `pushTokenUpdates` never sends the activity and may hold one. |
| 13 | An unsigned simulator build (`CODE_SIGNING_ALLOWED=NO`, i.e. every CI build) has **no App Group container**. cfprefsd silently denies `group.*` defaults suites (tests must inject a scratch suite), and SwiftData **TRAPS — it does not throw** — on a `groupContainer:` it cannot resolve, killing the app at launch. Probe `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` first and throw, so callers fall back. Only signed builds can prove the real container. |

## Before declaring done

`make lint` · `make build` · `make test`. On a machine without `xcodebuild`
(Linux, cloud sessions) run `make ci-linux` and say plainly that the compile
gates did not run. Never report a build result you did not observe.
