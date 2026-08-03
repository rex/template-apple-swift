import Foundation
import Testing

@testable import MyApp

/// `@MainActor` on the suite propagates to every `@Test` method, so the
/// main-actor store is reachable without an `await` at each call site.
/// `struct`, not `class`: Swift Testing builds a fresh suite instance per test.
///
/// `.serialized` because every store mutation republishes the shared App Group
/// snapshot — see the note in WidgetSyncTests.swift.
@MainActor
@Suite("CheckpointStore", .serialized)
struct CheckpointStoreTests {
    private func makeStore(seed: [Checkpoint] = []) -> CheckpointStore {
        CheckpointStore(persistence: InMemoryCheckpointStore(seed: seed))
    }

    @Test("a fresh store is idle and empty")
    func idleByDefault() {
        let store = makeStore()
        #expect(store.session.isActive == false)
        #expect(store.session.startedAt == nil)
        #expect(store.checkpoints.isEmpty)
        #expect(store.todayCount == 0)
    }

    @Test("starting a session marks it active")
    func startSession() {
        let store = makeStore()
        store.startSession()
        #expect(store.session.isActive)
        #expect(store.session.startedAt != nil)
    }

    @Test("starting twice keeps the original start date")
    func startIsIdempotent() throws {
        let store = makeStore()
        store.startSession()
        let first = try #require(store.session.startedAt)
        store.startSession()
        #expect(store.session.startedAt == first)
    }

    @Test("ending a session clears the start date")
    func endSession() {
        let store = makeStore()
        store.startSession()
        store.endSession()
        #expect(store.session.startedAt == nil)
        #expect(store.session.isActive == false)
    }

    @Test("logging increments today's count", arguments: [1, 3, 7])
    func logCheckpoints(count: Int) throws {
        let store = makeStore()
        store.startSession()
        for index in 0..<count {
            store.logCheckpoint(note: "note \(index)")
        }
        #expect(store.todayCount == count)
        #expect(store.checkpoints.count == count)

        let last = try #require(store.checkpoints.last)
        #expect(last.note == "note \(count - 1)")
    }

    @Test("checkpoints from earlier days do not count toward today")
    func todayCountIgnoresOlderDays() throws {
        let yesterday = try #require(
            Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )
        let store = makeStore(seed: [Checkpoint(timestamp: yesterday, note: "old")])

        #expect(store.checkpoints.count == 1)
        #expect(store.todayCount == 0)

        store.logCheckpoint(note: "new")
        #expect(store.todayCount == 1)
    }

    @Test("checkpoints survive a new store over the same persistence")
    func persistenceRoundTrip() throws {
        let persistence = InMemoryCheckpointStore()
        let first = CheckpointStore(persistence: persistence)
        first.logCheckpoint(note: "kept")

        let second = CheckpointStore(persistence: persistence)
        #expect(second.checkpoints.count == 1)

        let restored = try #require(second.checkpoints.first)
        #expect(restored.note == "kept")
    }

    @Test("removing by offset drops exactly the selected checkpoints")
    func removeAtOffsets() throws {
        let store = makeStore()
        for index in 0..<3 {
            store.logCheckpoint(note: "note \(index)")
        }
        store.removeCheckpoints(at: IndexSet([0, 2]))

        #expect(store.checkpoints.count == 1)

        let survivor = try #require(store.checkpoints.first)
        #expect(survivor.note == "note 1")
    }
}
