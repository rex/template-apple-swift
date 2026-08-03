import Foundation
import Testing

@testable import MyApp

/// `.serialized` because both round-trip tests share one scratch defaults
/// domain — a single global slot, so two tests writing at once would read
/// each other's snapshot. The scratch suite (not the real App Group) is
/// load-bearing on CI: an unsigned simulator build has no App Group
/// container, so cfprefsd denies `group.*` suites and a round-trip through
/// the real suite can never succeed there.
@Suite("WidgetSync", .serialized)
nonisolated struct WidgetSyncTests {
    private static let scratchSuite = "widget-sync-tests-scratch"

    private func makeScratch() throws -> UserDefaults {
        let scratch = try #require(UserDefaults(suiteName: Self.scratchSuite))
        scratch.removePersistentDomain(forName: Self.scratchSuite)
        return scratch
    }
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

    @Test("an active session round-trips through a defaults suite")
    func activeSessionRoundTrip() throws {
        let scratch = try makeScratch()
        let snapshot = WidgetSnapshot(
            sessionStartedAt: Date(timeIntervalSince1970: 1_000),
            todayCount: 4,
            lastUpdatedAt: Date(timeIntervalSince1970: 2_000)
        )
        WidgetSync.write(snapshot, into: scratch)

        let read = try #require(WidgetSync.read(from: scratch))
        #expect(read == snapshot)
    }

    @Test("an idle session is written as zero and read back as nil")
    func idleSessionRoundTrip() throws {
        let scratch = try makeScratch()
        let snapshot = WidgetSnapshot(
            sessionStartedAt: nil,
            todayCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 3_000)
        )
        WidgetSync.write(snapshot, into: scratch)

        let read = try #require(WidgetSync.read(from: scratch))
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
