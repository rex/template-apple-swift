// Always-on `CheckpointPersisting` implementations.
//
// These ship in every generated app, with or without the `swiftdata`
// component, so `CheckpointStore` always has somewhere to put its state.

import Foundation

/// Volatile persistence. The default for tests, previews and the macOS/watchOS
/// hosts before a real store is wired.
@MainActor
public final class InMemoryCheckpointStore: CheckpointPersisting {
    private var storage: [Checkpoint]

    public init(seed: [Checkpoint] = []) {
        self.storage = seed
    }

    public func load() throws -> [Checkpoint] {
        storage
    }

    public func save(_ checkpoints: [Checkpoint]) throws {
        storage = checkpoints
    }
}

/// Durable persistence with no framework dependency, backed by the App Group
/// suite so every host target sees the same array.
///
/// Fine for the low hundreds of checkpoints a template ships with; the moment
/// the domain grows a query surface, enable the `swiftdata` component instead
/// of adding indexes to a JSON blob.
@MainActor
public final class UserDefaultsCheckpointStore: CheckpointPersisting {
    private static let storageKey = "checkpoints.v1"

    private let defaults: UserDefaults

    /// Falls back to `.standard` when the App Group is unavailable (a preview
    /// process, or a target whose entitlement has not been added yet) so a
    /// missing entitlement degrades to process-local storage instead of a crash.
    public init(suiteName: String = WidgetAppGroup.suiteName) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func load() throws -> [Checkpoint] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return try JSONDecoder().decode([Checkpoint].self, from: data)
    }

    public func save(_ checkpoints: [Checkpoint]) throws {
        let data = try JSONEncoder().encode(checkpoints)
        defaults.set(data, forKey: Self.storageKey)
    }
}
