// CheckpointStore — the single mutation path for the Checkpoints domain.
//
// Nothing else writes session or checkpoint state. Views, App Intents,
// widgets-via-intent and the watch all route here, and every mutation
// republishes the App Group snapshot so extensions stay honest.

import Foundation

/// `@MainActor`, NOT `Sendable`: SwiftData's `ModelContext` is not `Sendable`
/// and `ModelContainer.mainContext` is main-actor-isolated, so a `Sendable`
/// protocol could only be satisfied with `@unchecked`. `CheckpointStore` is
/// main-actor anyway, so a main-actor protocol costs nothing and stays honest.
@MainActor
public protocol CheckpointPersisting {
    func load() throws -> [Checkpoint]
    func save(_ checkpoints: [Checkpoint]) throws
}

@MainActor
@Observable
public final class CheckpointStore {
    public private(set) var session: SessionState
    public private(set) var checkpoints: [Checkpoint]

    @ObservationIgnored private let persistence: any CheckpointPersisting

    /// Host-side observation hook, assigned once at launch. Every enabled
    /// mirror (Live Activity sync, watch context push, …) hangs off this one
    /// closure — the store stays component-agnostic and never owns a
    /// consumer's lifetime.
    @ObservationIgnored
    public var onSnapshot: (@MainActor (WidgetSnapshot) -> Void)?

    public init(persistence: any CheckpointPersisting) {
        self.persistence = persistence
        self.session = .idle
        self.checkpoints = (try? persistence.load()) ?? []
        publish()
    }

    /// Checkpoints logged on the current calendar day.
    public var todayCount: Int {
        checkpoints.filter(\.isToday).count
    }

    /// Idempotent: restarting an active session would reset the lock-screen
    /// timer and orphan the running Live Activity.
    public func startSession() {
        guard !session.isActive else { return }
        session.startedAt = .now
        publish()
    }

    public func endSession() {
        guard session.isActive else { return }
        session.startedAt = nil
        publish()
    }

    @discardableResult
    public func logCheckpoint(note: String?) -> Checkpoint {
        let checkpoint = Checkpoint(note: note)
        checkpoints.append(checkpoint)
        commit()
        return checkpoint
    }

    /// Shaped for SwiftUI's `.onDelete(perform:)` without importing SwiftUI
    /// into the store layer.
    public func removeCheckpoints(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where checkpoints.indices.contains(index) {
            checkpoints.remove(at: index)
        }
        commit()
    }

    // MARK: - Mutation plumbing

    private func commit() {
        try? persistence.save(checkpoints)
        publish()
    }

    private func publish() {
        let snapshot = WidgetSnapshot(
            sessionStartedAt: session.startedAt,
            todayCount: todayCount,
            lastUpdatedAt: .now
        )
        WidgetSync.write(snapshot)
        onSnapshot?(snapshot)
    }
}

@MainActor
extension CheckpointStore {
    /// The persistence every `@main` entry point should use unless it has a
    /// reason not to. The marker block below never names a SwiftData type, so
    /// pruning the `swiftdata` component leaves a file that still compiles
    /// without `import SwiftData`.
    public static func makeDefaultPersistence() -> any CheckpointPersisting {
        // @template:swiftdata BEGIN
        if let swiftData = SwiftDataCheckpointStore.makeDefault() {
            return swiftData
        }
        // @template:swiftdata END
        return UserDefaultsCheckpointStore()
    }
}
