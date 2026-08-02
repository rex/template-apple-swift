import Foundation
import Testing

@testable import MyApp

/// `.serialized` because the App Group suite is a single global slot: two tests
/// writing at once would read each other's snapshot. Whole-target parallelism
/// must also be off for this suite to stay deterministic alongside
/// CheckpointStoreTests, which republishes on every mutation: run `MyAppTests`
/// with `-parallel-testing-enabled NO`.
@Suite("WidgetSync", .serialized)
nonisolated struct WidgetSyncTests {
    @Test("keys and payload version are the frozen on-disk contract")
    func keyContract() {
        #expect(WidgetSyncKey.payloadVersion.rawValue == "sync.payloadVersion")
        #expect(WidgetSyncKey.sessionStartedAt.rawValue == "sync.sessionStartedAt")
        #expect(WidgetSyncKey.todayCount.rawValue == "sync.todayCount")
        #expect(WidgetSyncKey.lastUpdatedAt.rawValue == "sync.lastUpdatedAt")
        #expect(WidgetSync.payloadVersion == 1)
    }

    @Test("the App Group suite name matches the entitlement string")
    func suiteName() {
        #expect(WidgetAppGroup.suiteName.hasPrefix("group."))
    }

    @Test("an active session round-trips through the App Group")
    func activeSessionRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            sessionStartedAt: Date(timeIntervalSince1970: 1_000),
            todayCount: 4,
            lastUpdatedAt: Date(timeIntervalSince1970: 2_000)
        )
        WidgetSync.write(snapshot)

        let read = try #require(WidgetSync.read())
        #expect(read == snapshot)
    }

    @Test("an idle session is written as zero and read back as nil")
    func idleSessionRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            sessionStartedAt: nil,
            todayCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 3_000)
        )
        WidgetSync.write(snapshot)

        let read = try #require(WidgetSync.read())
        #expect(read.sessionStartedAt == nil)
        #expect(read.todayCount == 0)
    }

    @Test("a snapshot survives Codable as well as the App Group")
    func codableRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            sessionStartedAt: Date(timeIntervalSince1970: 4_000),
            todayCount: 9,
            lastUpdatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}
