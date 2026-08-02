# AGENTS.md (for /MyAppWatch)

Rules for the `MyAppWatch` watchOS application target. Inherits everything in
the root `AGENTS.md`; the nearest file wins on conflict.

## 1. Module overview

Single-target watchOS app (`WKApplication`). Owns its own `CheckpointStore`,
mirrors state to the phone through `WatchLink`, and feeds the complications in
`WatchComplications/` by writing the App Group snapshot on every mutation.

## 2. Commands

```bash
xcodebuild -project MyApp.xcodeproj -scheme MyAppWatch \
  -destination 'generic/platform=watchOS Simulator' build
```

## 3. Conventions

- Theme tokens only, `@Observable` only, explicit isolation on every type.
- Watch layouts assume a `ScrollView`; nothing here may rely on a
  `NavigationSplitView` or on hover.

## 4. Platform boundaries

- `WCSession` is not `Sendable` and `WCSessionDelegate` is not `@MainActor`.
  Never capture a `WCSession` inside `Task { @MainActor in … }` — snapshot the
  scalars you need inside the nonisolated callback first. `WatchLink` already
  does this; new delegate work must follow it.
- `updateApplicationContext` is latest-wins and is the default mirror;
  `sendMessage` needs `isReachable`; `transferUserInfo` is the guaranteed queue.
- `sessionDidBecomeInactive` / `sessionDidDeactivate` are iOS-only requirements
  and must stay behind `#if os(iOS)` or this target stops compiling.
- The watch target needs the App Group entitlement even before it reads the
  group, or `exportArchive` fails the phone/watch pairing check.
