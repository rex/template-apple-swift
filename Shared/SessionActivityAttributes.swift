// Live Activity attributes — shared by the iOS host and the LiveActivity
// extension, which are separate processes that must agree byte-for-byte.
//
// Component: `live-activity` (whole file). `#if os(iOS)` and NOT
// `canImport(ActivityKit)`: the module resolves on macOS and Mac Catalyst
// builds where the types themselves are unavailable, so `canImport` guards
// nothing.

import Foundation

#if os(iOS)
import ActivityKit

/// `nonisolated`: the system decodes this off the main actor.
public nonisolated struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var count: Int

        public init(startedAt: Date, count: Int) {
            self.startedAt = startedAt
            self.count = count
        }
    }

    public var sessionName: String

    public init(sessionName: String) {
        self.sessionName = sessionName
    }
}
#endif
