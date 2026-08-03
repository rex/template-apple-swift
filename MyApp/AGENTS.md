# AGENTS.md (for /MyApp)

Rules for the `MyApp` iOS application target. Inherits everything in the root
`AGENTS.md`; the nearest file wins on conflict.

## 1. Module overview

SwiftUI iOS app: session start/stop, checkpoint logging, history, settings.
Also the home of the App Intents (`Intents/`) and the Live Activity host
controller (`Services/`). Logic lives in `Shared/Store/CheckpointStore`.

## 2. Commands

```bash
xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' build
```

## 3. Conventions

- Every type carries explicit isolation. Views/`App` are `@MainActor`; anything
  witnessing a nonisolated synchronous requirement (`Identifiable`,
  `TimelineEntry`, `AppIntent` metadata) is `nonisolated`.
- `@Observable` + `@Environment(CheckpointStore.self)`. `ObservableObject`,
  `@StateObject` and `@EnvironmentObject` must not appear.
- Theme tokens only: no hex literals, no `.padding(12)`, no inline fonts.
- User-facing strings are plain literals; Xcode populates the String Catalog.
- Accessibility identifiers (`startSessionButton`, `endSessionButton`,
  `logCheckpointButton`, `checkpointNoteField`, `todayCountLabel`) are the
  contract with `UITests/` and the fastlane snapshot lane. Renaming one breaks
  screenshots; label text is localized and must never be matched instead.

## 4. Component seams

- `MyAppApp.swift` carries `swiftdata`, `nse` and `live-activity` marker blocks.
- `Views/SettingsView.swift` carries `store`, `account` and `health` blocks.
- `AppDelegate.swift` and `Services/LiveActivityController.swift` are whole-file
  component property (`nse`, `live-activity`). Nothing outside a marker block
  may reference them.
- Intents reach the store through `AppDependencyManager`, never a singleton.
