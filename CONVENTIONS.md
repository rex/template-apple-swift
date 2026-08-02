# CONVENTIONS

> Stable conventions. Changes require an ADR + review.
> Deterministic checks are enforced by pre-commit, `make lint` and CI — not by
> the agent. `.claude/rules/swift.md` is the short hard-stop version of this
> file; this is the reasoning behind it.
>
> This file is NOT regenerated at onboarding: it carries into your app as-is,
> with the identity tokens rewritten.

## Runtime

- Swift 6 language mode (`SWIFT_VERSION: '6.0'`), strict concurrency complete.
  Toolchain: Xcode 26.6 / Swift 6.3. XcodeGen ≥ 2.46.0.
- Dependencies: **SPM only**. CocoaPods and Carthage are forbidden.
- Install: `make bootstrap`. Build: `make build`. Test: `make test`.

## Layout

```
MyApp/                iOS app target
  Views/              SwiftUI screens — declarative only
  Services/           app-lifecycle glue (Live Activity, APNs)
  Intents/            App Intents + AppShortcutsProvider
MyAppMac/ MyAppWatch/ the other two app targets
<Extension>/          one directory per extension target, small and single-purpose
Shared/               everything used by more than one target
  Models/             value types
  Store/              CheckpointStore — the only mutation path
  Sync/               WidgetSync (App Group) + WatchLink (WCSession)
  Theme/              design tokens
  Capabilities/       optional capability modules (Store, Account, Health)
Tests/ UITests/       mirror the source layout
```

Views → Store → persistence. No business logic in a view; no view types inside
`Shared/Store`.

## Concurrency

- Every type is explicitly `@MainActor` or `nonisolated`. Nothing depends on
  `SWIFT_DEFAULT_ACTOR_ISOLATION`, so the same sources compile under Xcode 26's
  new default and the legacy one.
- `TimelineProvider` conformances, the NSE subclass, the `WCSessionDelegate`,
  `WidgetSync`, `SessionActivityAttributes` and `Theme` are `nonisolated` —
  they run in extension processes and off the main actor.
- `async`/`await` is the idiom. Combine only when bridging something that has
  no async surface, and never as a new dependency between our own types.
- `@unchecked Sendable` needs a comment justifying it; `nonisolated(unsafe)`
  needs an ADR.

## SwiftUI

- `@Observable` + `@State` / `@Environment`. `ObservableObject`, `@Published`,
  `@StateObject` and `@EnvironmentObject` are forbidden and gate-checked.
- Views read from a store and call intents on it. They do not persist, network,
  or compute policy.
- Every widget/complication view calls `.containerBackground(_:for: .widget)`.

## Design tokens

- All colors, fonts, spacing and radii come from `Theme`. No hex literals, no
  magic numbers, no ad-hoc `.font(.system(size:))`.
- `Theme.registerFonts()` is a documented no-op called from every `@main` and
  every `WidgetBundle.init()`, so bundled fonts can drop in later without
  archaeology.
- System fonts only in v1 — nothing ships a `.ttf`.

## Strings

- User-facing text lives in the String Catalog (`Shared/Resources/*.xcstrings`).
  A literal in a view is a localization bug.
- Log messages and identifiers are not localized and stay in code.

## Persistence + cross-process state

- `CheckpointStore` is the **only** mutation path. Every mutation writes
  through `WidgetSync` to the App Group so widgets and complications see it.
- Extensions read `WidgetSync`; only hosts and the NSE write it.
- `WCSession` payloads stay small (the cap is ~65 KB) and carry a summary, not
  a history. `updateApplicationContext` keeps only the latest value.

## Project structure

- `project.yml` + `xcodegen/components/*.yml` are the source of truth.
  `MyApp.xcodeproj` is a build artifact: never hand-edited, never committed.
- `Info.plist` and `.entitlements` are generated from YAML and gitignored.
  `PrivacyInfo.xcprivacy` is hand-authored, one per bundle.
- `Config/Shared.xcconfig` owns `DEVELOPMENT_TEAM`; `Config/Versions.xcconfig`
  owns `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` and is written by CI.
  Those three keys appear nowhere else — an `.xcconfig` is the lowest layer of
  Xcode's precedence and is silently overridden by `project.yml`.

## Testing

- Swift Testing (`@Test` / `#expect`) for units. XCTest survives only where the
  framework requires it (XCUITest).
- UI tests live in their own scheme so `make test` stays fast; the same target
  drives fastlane `snapshot`.
- Tests mirror source layout. No test that only exercises test doubles.

## Errors + logging

- Typed, domain-specific errors. No stringly-typed failures.
- `os.Logger` with a per-subsystem category. Never log tokens, credentials,
  health data or full payloads.
- The NSE uses `os.Logger` directly — it pulls a deliberately thin subset of
  `Shared/` and does not import the app's logging wrapper.

## File size

250 lines soft (a refactor signal), 400 hard (a blocking failure). Split by
responsibility, not by line count. Enforced by `make check-architecture`.

## What NOT to put in prompts (the tooling's job)

- Formatting and import order — SwiftFormat / SwiftLint via `make lint`.
- Line limits — `check_architecture.py`.
- Version bumps — `bump_version.py` / `check_version_bumped.py`.
- Bundle-ID and App Group shape — `template/verify.py`.
