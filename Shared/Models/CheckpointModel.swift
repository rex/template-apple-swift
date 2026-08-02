// SwiftData mirror of the `Checkpoint` value type.
//
// Component: `swiftdata` (whole file — no markers). Nothing outside
// `SwiftDataCheckpointStore` may hold one of these: `PersistentModel` does not
// inherit `Sendable`, so `@Model` instances stay main-actor-confined and the
// `Checkpoint` struct is the only thing that crosses a boundary.

import Foundation
import SwiftData

/// `nonisolated` is load-bearing. `PersistentModel` refines `Hashable` and
/// `Equatable`, whose requirements are nonisolated and synchronous; under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` an unannotated `@Model` class
/// becomes a main-actor witness for them and fails to compile.
///
/// `#Index` is iOS 18 / macOS 15 / watchOS 11 — exactly the template's floors.
/// Lowering a floor means deleting the macro, not conditionalising it.
@Model
internal nonisolated final class CheckpointRecord {
    #Index<CheckpointRecord>([\.timestamp])

    var id: UUID
    var timestamp: Date
    var note: String?

    init(id: UUID, timestamp: Date, note: String?) {
        self.id = id
        self.timestamp = timestamp
        self.note = note
    }
}

extension CheckpointRecord {
    /// The value type is the currency; these two functions are the only place
    /// a persistent model is minted or read.
    var asCheckpoint: Checkpoint {
        Checkpoint(id: id, timestamp: timestamp, note: note)
    }

    static func make(from checkpoint: Checkpoint) -> CheckpointRecord {
        CheckpointRecord(id: checkpoint.id, timestamp: checkpoint.timestamp, note: checkpoint.note)
    }
}
