// Checkpoint — the durable unit of the Checkpoints domain.

import Foundation

/// One logged moment.
///
/// This value type is the currency that crosses every boundary: the store
/// holds an array of them, the SwiftData `@Model` mirror maps to and from
/// them, and tests build them directly. Nothing outside `Shared/Store`
/// constructs a persistence-layer type.
public nonisolated struct Checkpoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var note: String?

    public init(id: UUID = UUID(), timestamp: Date = .now, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.note = note
    }
}

nonisolated extension Checkpoint {
    /// Whether this checkpoint falls on the current calendar day.
    public var isToday: Bool {
        Calendar.current.isDateInToday(timestamp)
    }
}
