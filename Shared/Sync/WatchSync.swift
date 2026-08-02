// WatchSync — the iOS ↔ watchOS payload schema and channel policy.
//
// Component: `watch` (whole file). WatchConnectivity exists on iOS and watchOS
// only; the explicit `os()` checks sit alongside `canImport` because a module
// resolving is not the same as its types being usable (see
// SessionActivityAttributes.swift for the same trap with ActivityKit).

import Foundation

#if (os(iOS) || os(watchOS)) && canImport(WatchConnectivity)

/// The Sendable value extracted from every `WCSession` callback before any
/// actor hop. `WCSession` and `[String: Any]` are both non-`Sendable`, so this
/// type is the boundary.
public nonisolated struct WatchPayload: Codable, Equatable, Sendable {
    public var sessionStartedAt: Date?
    public var todayCount: Int

    public init(sessionStartedAt: Date? = nil, todayCount: Int = 0) {
        self.sessionStartedAt = sessionStartedAt
        self.todayCount = todayCount
    }

    public init(_ snapshot: WidgetSnapshot) {
        self.sessionStartedAt = snapshot.sessionStartedAt
        self.todayCount = snapshot.todayCount
    }
}

public nonisolated enum WatchSync {
    /// WatchConnectivity rejects anything at or above 65_536 bytes with
    /// `WCError.payloadTooLarge`. Mirror scalars only — never ship history,
    /// images, or an encoded `[Checkpoint]` across this link.
    public static let maxPayloadBytes = 65_536

    /// Dictionary keys are the wire contract between the two apps. Both sides
    /// ship in the same version, so there is no version field: change a key and
    /// change both targets in the same commit.
    public nonisolated enum Key {
        public static let sessionStartedAt = "sessionStartedAt"
        public static let todayCount = "todayCount"
    }

    public static func encode(_ payload: WatchPayload) -> [String: Any] {
        [
            Key.sessionStartedAt: payload.sessionStartedAt?.timeIntervalSince1970 ?? 0,
            Key.todayCount: payload.todayCount,
        ]
    }

    public static func decode(_ dictionary: [String: Any]) -> WatchPayload {
        let unix = dictionary[Key.sessionStartedAt] as? TimeInterval ?? 0
        return WatchPayload(
            sessionStartedAt: unix > 0 ? Date(timeIntervalSince1970: unix) : nil,
            todayCount: dictionary[Key.todayCount] as? Int ?? 0
        )
    }

    /// Approximate — binary plist framing is what WatchConnectivity measures,
    /// and it is close enough to catch a payload that grew a collection.
    public static func isWithinPayloadLimit(_ dictionary: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .binary,
            options: 0
        ) else { return false }
        return data.count < maxPayloadBytes
    }
}

#endif
