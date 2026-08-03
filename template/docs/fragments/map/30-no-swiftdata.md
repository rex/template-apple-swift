Persistence is in-memory (`InMemoryCheckpointStore`). Adding SwiftData later
means a new `CheckpointPersisting` conformance — the protocol seam is already
there and `@MainActor` for `ModelContext`'s sake.
