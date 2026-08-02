# Shared

> **Shared module — read the Public API below rather than the internals. Changing a public signature is an ADR.** Editing rules: `Shared/AGENTS.md`. Repo map: `MAP.md`.

Cross-target Swift compiled into every app and extension target: the Checkpoints
domain, the cross-process bridges, and the design-token chokepoint. Consumed by
`MyApp/`, `MyAppMac/`, `MyAppWatch/`, and all five extensions.

## Why this exists

Eight targets have to agree on one domain model, one App Group key set, one
palette, and one configuration story. Anything used by more than one target
lives here so the copies cannot drift.

## Public API

- `CheckpointStore` (`Store/`) — `@MainActor @Observable`. The **only** mutation
  path: `startSession()`, `endSession()`, `logCheckpoint(note:)`,
  `removeCheckpoints(at:)`, plus `session` / `checkpoints` / `todayCount`.
- `CheckpointPersisting` (`Store/`) — `@MainActor` persistence seam.
  `InMemoryCheckpointStore`, `UserDefaultsCheckpointStore`, and (component
  `swiftdata`) `SwiftDataCheckpointStore` implement it.
- `Checkpoint`, `SessionState` (`Models/`) — `Codable`/`Sendable` value types.
- `WidgetSync` / `WidgetSnapshot` / `WidgetAppGroup` / `WidgetSyncKey` (`Sync/`)
  — the App Group bridge. Hosts and the NSE write; extensions read.
- `WatchLink` / `WatchPayload` / `WatchSync` (component `watch`) — WatchConnectivity;
  `SessionActivityAttributes` (component `live-activity`) — Live Activity wire type.
- `Theme` (`Theme/`) — design tokens. `ColorPalette` and `Color(hex:)` are internal.
- `Env` (`Env/`) — runtime configuration. `Log` — `os.Logger` categories.
- `Capabilities/{Store,Account,Health}` — optional components, each a whole
  directory that disappears when its component is off.

## Architecture

```
MyApp / MyAppMac / MyAppWatch ──┐                     ┌── HomeWidget / MacWidget
                                ↓                     ↓   WatchComplications
                             Shared/          (read-only, App Group)
                                ↑                     ↑   LiveActivity
NotificationService ────────────┘                     └── (own processes)
```

Depends on Foundation, SwiftUI, and the per-component frameworks only.

## Files

- `Models/` — value types plus the `swiftdata` `@Model` mirror.
- `Store/` — `CheckpointStore` and every `CheckpointPersisting` implementation.
- `Sync/` — `WidgetSync` (App Group), `WatchSync`/`WatchLink` (WatchConnectivity).
- `Theme/`, `Env/`, `Capabilities/` — tokens, configuration, optional components.
  `SessionActivityAttributes.swift` and `Log.swift` are single-file surfaces.

## Invariants

- Every type carries explicit isolation: `@MainActor` or `nonisolated`.
- `CheckpointStore` is the only writer; every mutation republishes `WidgetSync`.
- Extensions never open the SwiftData container — they read the App Group snapshot.
- No `import UIKit` / `import AppKit` anywhere, guarded or not.
- No `ObservableObject`, `@Published`, `@StateObject`, or `@EnvironmentObject`.
- Views read `Theme.*` only: no hex literals, magic numbers, or inline fonts.

## Common tasks

- **Add a domain field**: `Models/` → `CheckpointStore` → `WidgetSnapshot` +
  `WidgetSyncKey` (bump `WidgetSync.payloadVersion`) → `WatchPayload` → tests.
- **Add a persistence backend**: conform to `CheckpointPersisting`; nothing else.
- **Re-skin**: `Theme/ColorPalette.swift` and `Theme/Theme.swift`. **Add config**:
  a typed accessor on `Env` plus a key in `Environment.example.plist`.

## Gotchas

- App Group `UserDefaults` is not KVO-synchronised across processes. Extensions
  re-read on every timeline invocation (fine); a host app must re-read on
  foreground rather than trusting a cached value.
- WatchConnectivity payloads must stay under 65 KB — scalars, never history.
- `Environment.plist` is gitignored but ships inside the `.ipa`: endpoints and
  flags only, never a credential.
