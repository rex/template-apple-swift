// Log — the os.Logger namespace. Every module logs through it; no print().
//
// The subsystem is the app's bundle ID and is deliberately NOT
// `Bundle.main.bundleIdentifier`: in an extension that would resolve to the
// extension's own ID, and `log stream --subsystem com.example.myapp` would
// then miss half the processes that make up the app.

import Foundation
import os

public nonisolated enum Log {
    public static let subsystem = "com.example.myapp"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let data = Logger(subsystem: subsystem, category: "data")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let widget = Logger(subsystem: subsystem, category: "widget")
    public static let watch = Logger(subsystem: subsystem, category: "watch")
    public static let activity = Logger(subsystem: subsystem, category: "activity")
    public static let push = Logger(subsystem: subsystem, category: "push")
    public static let purchases = Logger(subsystem: subsystem, category: "purchases")
    public static let account = Logger(subsystem: subsystem, category: "account")
    public static let health = Logger(subsystem: subsystem, category: "health")

    /// djb2 hash keeping the last `keep` characters visible. Use for any
    /// identifier you want correlatable across log lines but not readable in
    /// Console.app — Apple user IDs, device IDs, transaction IDs.
    ///
    /// Health samples and auth tokens are never logged at all, redacted or not.
    public static func redactID(_ id: String, keep: Int = 4) -> String {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%llx-%@", hash, String(id.suffix(keep)))
    }
}
