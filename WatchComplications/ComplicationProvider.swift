import SwiftUI
import WidgetKit

nonisolated struct ComplicationEntry: TimelineEntry {
    let date: Date
    let sessionStartedAt: Date?
    let todayCount: Int
}

/// `nonisolated`: `TimelineProvider`'s requirements are nonisolated and
/// synchronous. Complications read the App Group snapshot the watch app writes
/// on every store mutation — they never reach across to the phone themselves.
nonisolated struct ComplicationProvider: TimelineProvider {
    private static let reloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-900), todayCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let policy: TimelineReloadPolicy = .after(.now.addingTimeInterval(Self.reloadInterval))
        completion(Timeline(entries: [Self.currentEntry()], policy: policy))
    }

    private static func currentEntry() -> ComplicationEntry {
        let snapshot = WidgetSync.read()
        return ComplicationEntry(
            date: .now,
            sessionStartedAt: snapshot?.sessionStartedAt,
            todayCount: snapshot?.todayCount ?? 0
        )
    }
}
