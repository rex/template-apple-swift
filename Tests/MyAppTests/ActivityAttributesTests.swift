// Component: `live-activity` (whole file — components own test files outright,
// never via markers).

#if os(iOS)
import ActivityKit
import Foundation
import Testing

@testable import MyApp

/// The host app and the LiveActivity extension are separate processes that
/// encode and decode this type independently, so the wire shape is a contract
/// and not an implementation detail.
@Suite("SessionActivityAttributes")
nonisolated struct ActivityAttributesTests {
    @Test("ContentState round-trips through JSON")
    func contentStateCodable() throws {
        let state = SessionActivityAttributes.ContentState(
            startedAt: Date(timeIntervalSince1970: 1_000),
            count: 7
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            SessionActivityAttributes.ContentState.self,
            from: data
        )
        #expect(decoded == state)
    }

    @Test("ContentState is Hashable, which ActivityAttributes requires")
    func contentStateHashable() {
        let a = SessionActivityAttributes.ContentState(startedAt: .now, count: 1)
        let b = a
        #expect(Set([a, b]).count == 1)
    }

    @Test("attributes carry the session name across the process boundary")
    func attributesCodable() throws {
        let attributes = SessionActivityAttributes(sessionName: "Focus")
        let data = try JSONEncoder().encode(attributes)
        let decoded = try JSONDecoder().decode(SessionActivityAttributes.self, from: data)
        #expect(decoded.sessionName == "Focus")
    }

    @Test("a store snapshot maps cleanly onto a ContentState")
    func snapshotMapping() {
        let snapshot = WidgetSnapshot(
            sessionStartedAt: Date(timeIntervalSince1970: 2_000),
            todayCount: 3,
            lastUpdatedAt: .now
        )
        let started = snapshot.sessionStartedAt ?? .now
        let state = SessionActivityAttributes.ContentState(
            startedAt: started,
            count: snapshot.todayCount
        )
        #expect(state.startedAt == snapshot.sessionStartedAt)
        #expect(state.count == 3)
    }
}
#endif
