`Shared/Store/SwiftDataCheckpointStore.swift` — SwiftData persistence.
`CheckpointPersisting` is `@MainActor` because `ModelContext` is not `Sendable`.
