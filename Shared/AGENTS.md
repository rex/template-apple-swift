# AGENTS.md (for `/Shared`)

Rules for the shared module. Inherits everything in the root `AGENTS.md`.

## 1. Module overview

- **What:** the Checkpoints domain (`CheckpointStore` + value types), the two
  cross-process bridges (`WidgetSync`, `WatchLink`), the design-token
  chokepoint (`Theme`), configuration (`Env`), logging (`Log`), and the three
  optional capability directories.
- **Compiled into:** every app and extension target. Anything you add here is
  eight targets' problem.
- **Public API contract:** `Shared/README.md`.

## 2. Isolation (the rule that breaks builds)

- **Every type carries explicit isolation** — `@MainActor` or `nonisolated`.
  Never rely on `SWIFT_DEFAULT_ACTOR_ISOLATION`; the template must compile
  identically under both settings.
- These MUST be `nonisolated`: `WidgetSync` and its three companions,
  `SessionActivityAttributes`, `Theme` and every nested token namespace,
  `Env`, `Log`, the `@Model` mirror, and the `WCSessionDelegate` conformance.
  Nesting does not inherit isolation — annotate nested enums individually.
- `WCSession` is not `Sendable` and `WCSessionDelegate` is not `@MainActor`.
  Snapshot the scalars you need inside the nonisolated callback, then hop.
  `Task { @MainActor in … session.isReachable … }` is a hard Swift 6 error.
- Guard platform-specific code with `#if os(...)`, never `#if canImport(...)`:
  ActivityKit, HealthKit and friends import on platforms where their types are
  unusable, so `canImport` guards nothing.

## 3. Coding conventions

- SwiftUI only. `@Observable` + `@State` + `.environment(_:)`. No
  `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject`.
- No `import UIKit` or `import AppKit` — guarded or otherwise.
- Views read `Theme.color/font/spacing/radius/size/stroke/animation/opacity`.
  A hex literal, a `.padding(12)`, or a `.font(.system(size:))` in a view is a
  review failure. `ColorPalette` and `Color(hex:)` are internal for this reason.
- User-facing strings are plain literals inside SwiftUI views so Xcode extracts
  them into the String Catalog. Helpers return values, not display copy.
- Business logic lives in stores and services; views stay declarative.
- 4-space indent, explicit access control, trailing commas on multiline literals.
- Comments explain constraints the code cannot show. Never narrate the code.

## 4. Component discipline

- Component-owned code is **whole-file or whole-directory** wherever possible.
  `Capabilities/Store`, `Capabilities/Account` and `Capabilities/Health` are
  deleted outright when their component is off.
- The only marker file here is `Store/CheckpointStore.swift`
  (`swiftdata` impl selection + `live-activity` notification). Grammar is exact:
  `// @template:<id> BEGIN` / `// @template:<id> END`, whole-line, never nested.
- **Code inside a marker block must be removable leaving compiling code
  behind.** A block that names a type from a component-only `import` breaks that
  rule — go through a component-owned factory instead.

## 5. Persistence and cross-process state

- `CheckpointStore` is the only mutation path, and every mutation republishes
  the App Group snapshot. Do not add a second writer.
- Extensions read `WidgetSync` only. Opening the SwiftData container from a
  timeline provider is the classic cause of widget timeouts.
- Keychain for anything credential-shaped; `UserDefaults` never.
- `Environment.plist` is bundled into the app and readable by anyone with the
  `.ipa`. Endpoints and feature flags only.

## 6. Testing

- Swift Testing (`@Test`, `#expect`, `#require`, `@Test(arguments:)`). XCTest is
  for `UITests/` only.
- Suites are `struct`s; add `@MainActor` when the suite touches the store.
- Suites that write the App Group are `.serialized`, and `MyAppTests` runs with
  `-parallel-testing-enabled NO` — the suite is a single global slot.
- A component's tests are whole files owned by that component, never markers.

## 7. Before declaring done

Run the build commands in the root `AGENTS.md` §3 for iOS, macOS and watchOS.
Shared code that only compiles for one platform is the most common regression
in this directory.
