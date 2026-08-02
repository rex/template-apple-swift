// SwiftData-backed persistence.
//
// Component: `swiftdata` (whole file — no markers).
//
// Widgets, complications and the NSE must NEVER open this container: reading a
// SwiftData store from a timeline provider is the classic cause of widget
// timeouts. They read the App Group snapshot (`WidgetSync`) instead.

import Foundation
import SwiftData

/// `@MainActor` because it uses `container.mainContext`, which is itself
/// main-actor-isolated. A background `@ModelActor` is the upgrade path once
/// writes stop being user-initiated.
@MainActor
public final class SwiftDataCheckpointStore: CheckpointPersisting {
    private static let schema = Schema([CheckpointRecord.self])

    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Convenience used by `CheckpointStore.makeDefaultPersistence()`. Returns
    /// `nil` rather than throwing so the caller's marker block can fall back to
    /// the always-on store without naming a SwiftData type.
    public static func makeDefault() -> SwiftDataCheckpointStore? {
        guard let container = try? makeContainer() else { return nil }
        return SwiftDataCheckpointStore(container: container)
    }

    /// No migration plan by design — the template ships one schema version.
    /// `groupContainer:` (not a hand-built App Group file URL) is what makes
    /// the same store reachable from every host target.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        // An in-memory store never touches the App Group, and asking for one in
        // a test host that lacks the entitlement fails container creation.
        let group: ModelConfiguration.GroupContainer = inMemory
            ? .none
            : .identifier(WidgetAppGroup.suiteName)

        let configuration = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: group,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public func load() throws -> [Checkpoint] {
        let descriptor = FetchDescriptor<CheckpointRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try container.mainContext.fetch(descriptor).map(\.asCheckpoint)
    }

    /// Replace-all rather than diff: the template's arrays are small and a
    /// correct diff needs a stable identity story this domain does not have yet.
    public func save(_ checkpoints: [Checkpoint]) throws {
        let context = container.mainContext
        try context.delete(model: CheckpointRecord.self)
        for checkpoint in checkpoints {
            context.insert(CheckpointRecord.make(from: checkpoint))
        }
        try context.save()
    }
}
