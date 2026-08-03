import SwiftUI
import WidgetKit

/// `nonisolated` because `TimelineEntry`'s `date` requirement is nonisolated
/// and synchronous.
nonisolated struct HomeWidgetEntry: TimelineEntry {
    let date: Date
    let sessionStartedAt: Date?
    let todayCount: Int
}

/// `nonisolated` because every `TimelineProvider` requirement is nonisolated
/// and synchronous — a main-actor witness is a hard Swift 6 error.
///
/// The provider reads the App Group snapshot only. Opening the SwiftData store
/// from here is the classic cause of widget timeouts.
nonisolated struct HomeWidgetProvider: TimelineProvider {
    private static let reloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-900), todayCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        // The elapsed timer self-advances; a reload only buys a fresh count, so
        // the host pushes `WidgetCenter.reloadTimelines(ofKind:)` on mutation
        // and this interval is just the safety net.
        let policy: TimelineReloadPolicy = .after(.now.addingTimeInterval(Self.reloadInterval))
        completion(Timeline(entries: [Self.currentEntry()], policy: policy))
    }

    private static func currentEntry() -> HomeWidgetEntry {
        let snapshot = WidgetSync.read()
        return HomeWidgetEntry(
            date: .now,
            sessionStartedAt: snapshot?.sessionStartedAt,
            todayCount: snapshot?.todayCount ?? 0
        )
    }
}

@MainActor
struct HomeWidget: Widget {
    static let kind = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HomeWidgetProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Checkpoints")
        .description("Your live session and today's checkpoint count.")
        // `accessoryCorner` is watchOS-only and `systemExtraLargePortrait` is
        // an iOS 27 beta case — neither may appear in an iOS array.
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

#Preview("small", as: .systemSmall) {
    HomeWidget()
} timeline: {
    HomeWidgetEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-600), todayCount: 4)
    HomeWidgetEntry(date: .now, sessionStartedAt: nil, todayCount: 4)
}

#Preview("rectangular", as: .accessoryRectangular) {
    HomeWidget()
} timeline: {
    HomeWidgetEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-600), todayCount: 4)
}
