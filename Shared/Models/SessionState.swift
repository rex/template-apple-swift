// SessionState — the live half of the Checkpoints domain.

import Foundation

/// A session is nothing more than "when did it start, or has it not".
///
/// Deliberately not an enum: `startedAt` is what every surface actually
/// renders (`Text(startedAt, style: .timer)` self-advances on the lock
/// screen, in a widget, and in a complication without any further update).
public nonisolated struct SessionState: Codable, Equatable, Sendable {
    public var startedAt: Date?

    public var isActive: Bool { startedAt != nil }

    public init(startedAt: Date? = nil) {
        self.startedAt = startedAt
    }

    /// Idle state. Named so call sites read as intent rather than as `nil`.
    public static let idle = SessionState(startedAt: nil)
}
