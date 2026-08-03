// Component: `swiftdata` (whole file — components own test files outright,
// never via markers).

import Foundation
import SwiftData
import Testing

@testable import MyApp

/// In-memory containers only: `makeContainer(inMemory: true)` deliberately asks
/// for no App Group, because a test host without the entitlement cannot open
/// the shared container.
@MainActor
@Suite("SwiftDataCheckpointStore")
struct SwiftDataStoreTests {
    private func makeStore() throws -> SwiftDataCheckpointStore {
        let container = try SwiftDataCheckpointStore.makeContainer(inMemory: true)
        return SwiftDataCheckpointStore(container: container)
    }

    @Test("a fresh container loads nothing")
    func emptyLoad() throws {
        let store = try makeStore()
        let loaded = try store.load()
        #expect(loaded.isEmpty)
    }

    @Test("save then load round-trips every field")
    func roundTrip() throws {
        let store = try makeStore()
        let checkpoint = Checkpoint(
            timestamp: Date(timeIntervalSince1970: 1_000),
            note: "persisted"
        )
        try store.save([checkpoint])

        let loaded = try store.load()
        #expect(loaded.count == 1)

        let first = try #require(loaded.first)
        #expect(first.id == checkpoint.id)
        #expect(first.note == "persisted")
        #expect(first.timestamp == checkpoint.timestamp)
    }

    @Test("load returns checkpoints oldest first")
    func loadIsSorted() throws {
        let store = try makeStore()
        let newer = Checkpoint(timestamp: Date(timeIntervalSince1970: 2_000), note: "newer")
        let older = Checkpoint(timestamp: Date(timeIntervalSince1970: 1_000), note: "older")
        try store.save([newer, older])

        let notes = try store.load().compactMap(\.note)
        #expect(notes == ["older", "newer"])
    }

    @Test("save replaces the previous contents rather than appending")
    func saveReplaces() throws {
        let store = try makeStore()
        try store.save([Checkpoint(note: "first")])
        try store.save([Checkpoint(note: "second")])

        let loaded = try store.load()
        #expect(loaded.count == 1)

        let only = try #require(loaded.first)
        #expect(only.note == "second")
    }

    @Test("CheckpointStore drives SwiftData end to end")
    func throughCheckpointStore() throws {
        let persistence = try makeStore()
        let store = CheckpointStore(persistence: persistence)
        store.startSession()
        store.logCheckpoint(note: "via the store")

        #expect(store.todayCount == 1)
        #expect(try persistence.load().count == 1)

        let reloaded = CheckpointStore(persistence: persistence)
        #expect(reloaded.checkpoints.count == 1)
    }
}
