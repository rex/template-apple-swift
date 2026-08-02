## Cross-target contracts

| Contract | File | Rule |
|---|---|---|
| App Group bridge | `Shared/Sync/WidgetSync.swift` | hosts write, extensions read; `nonisolated` throughout |
| Mutation path | `Shared/Store/CheckpointStore.swift` | `@MainActor @Observable`; the ONLY writer |
| Design tokens | `Shared/Theme/Theme.swift` | `Theme.color/font/spacing/radius`; no literals in views |
| App Intents | `{{app_name}}/Intents/CheckpointIntents.swift` | `static let` metadata; every phrase carries `\(.applicationName)` |

`CheckpointStore.onSnapshot` is the always-on fan-out seam: it is assigned once
in `{{app_name}}App` and each consumer hangs off it. Removing a consumer leaves
compiling code.
