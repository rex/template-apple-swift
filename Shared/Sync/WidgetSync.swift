// WidgetSync — the App Group bridge, and the ONLY cross-process channel.
//
// Host apps (iOS / macOS / watchOS) and the Notification Service Extension
// write; widgets, complications and the Live Activity read. `@Observable`
// stores cannot be observed across process boundaries — an extension runs in
// its own address space, so this UserDefaults suite is the whole contract.
//
// Every target that touches this file MUST declare the App Group in its
// entitlements: com.apple.security.application-groups = [group.com.example.myapp]

import Foundation

/// One string, eight entitlements. Change it here and in every `.entitlements`.
public nonisolated enum WidgetAppGroup {
    public static let suiteName = "group.com.example.myapp"
}

/// Raw values are the on-disk contract. Renaming one is a breaking change that
/// requires bumping `WidgetSync.payloadVersion`.
public nonisolated enum WidgetSyncKey: String {
    case payloadVersion   = "sync.payloadVersion"    // Int, currently 1
    case sessionStartedAt = "sync.sessionStartedAt"  // Double unix seconds; 0 = no session
    case todayCount       = "sync.todayCount"        // Int
    case lastUpdatedAt    = "sync.lastUpdatedAt"     // Double unix seconds
}

public nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var sessionStartedAt: Date?
    public var todayCount: Int
    public var lastUpdatedAt: Date

    public init(sessionStartedAt: Date? = nil, todayCount: Int = 0, lastUpdatedAt: Date = .now) {
        self.sessionStartedAt = sessionStartedAt
        self.todayCount = todayCount
        self.lastUpdatedAt = lastUpdatedAt
    }
}

/// `nonisolated` is load-bearing: `read()` is called from inside `nonisolated`
/// `TimelineProvider` conformances and from the Notification Service Extension.
/// If `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` were allowed to isolate this
/// enum, every widget target would fail with "call to main actor-isolated
/// static method in a synchronous nonisolated context".
public nonisolated enum WidgetSync {
    public static let payloadVersion = 1

    /// Computed, not stored: a stored `UserDefaults` static would be global
    /// mutable state, and the suite is cheap to resolve.
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetAppGroup.suiteName)
    }

    /// `into` exists for tests only: an unsigned simulator build (CI runs with
    /// `CODE_SIGNING_ALLOWED=NO`) has no App Group container, so cfprefsd
    /// denies the group suite and a round-trip can never succeed there. Tests
    /// pass a scratch suite; production callers never pass anything.
    public static func write(_ snapshot: WidgetSnapshot, into overrideDefaults: UserDefaults? = nil) {
        guard let defaults = overrideDefaults ?? defaults else { return }
        defaults.set(payloadVersion, forKey: WidgetSyncKey.payloadVersion.rawValue)
        defaults.set(snapshot.sessionStartedAt?.timeIntervalSince1970 ?? 0,
                     forKey: WidgetSyncKey.sessionStartedAt.rawValue)
        defaults.set(snapshot.todayCount, forKey: WidgetSyncKey.todayCount.rawValue)
        defaults.set(snapshot.lastUpdatedAt.timeIntervalSince1970,
                     forKey: WidgetSyncKey.lastUpdatedAt.rawValue)
    }

    /// `nil` means "nothing written yet, or written by an incompatible build".
    /// Callers render their placeholder rather than inventing a zero state.
    public static func read(from overrideDefaults: UserDefaults? = nil) -> WidgetSnapshot? {
        guard let defaults = overrideDefaults ?? defaults,
              defaults.integer(forKey: WidgetSyncKey.payloadVersion.rawValue) == payloadVersion
        else { return nil }

        let startedUnix = defaults.double(forKey: WidgetSyncKey.sessionStartedAt.rawValue)
        return WidgetSnapshot(
            sessionStartedAt: startedUnix > 0 ? Date(timeIntervalSince1970: startedUnix) : nil,
            todayCount: defaults.integer(forKey: WidgetSyncKey.todayCount.rawValue),
            lastUpdatedAt: Date(
                timeIntervalSince1970: defaults.double(forKey: WidgetSyncKey.lastUpdatedAt.rawValue)
            )
        )
    }
}
