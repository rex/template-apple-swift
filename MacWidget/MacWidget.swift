import SwiftUI
import WidgetKit

nonisolated struct MacWidgetEntry: TimelineEntry {
    let date: Date
    let sessionStartedAt: Date?
    let todayCount: Int
}

/// `nonisolated` for the same reason as the iOS provider: every
/// `TimelineProvider` requirement is nonisolated and synchronous.
nonisolated struct MacWidgetProvider: TimelineProvider {
    private static let reloadInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> MacWidgetEntry {
        MacWidgetEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-900), todayCount: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacWidgetEntry) -> Void) {
        completion(Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacWidgetEntry>) -> Void) {
        let policy: TimelineReloadPolicy = .after(.now.addingTimeInterval(Self.reloadInterval))
        completion(Timeline(entries: [Self.currentEntry()], policy: policy))
    }

    /// Same App Group as every other reader. On macOS the group string carries
    /// no team prefix, matching the single spelling used on iOS and watchOS —
    /// mixing the two forms is what breaks cross-process reads.
    private static func currentEntry() -> MacWidgetEntry {
        let snapshot = WidgetSync.read()
        return MacWidgetEntry(
            date: .now,
            sessionStartedAt: snapshot?.sessionStartedAt,
            todayCount: snapshot?.todayCount ?? 0
        )
    }
}

@MainActor
struct MacWidget: Widget {
    static let kind = "MacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MacWidgetProvider()) { entry in
            MacWidgetView(entry: entry)
        }
        .configurationDisplayName("Checkpoints")
        .description("Your live session and today's checkpoint count.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@MainActor
struct MacWidgetView: View {
    let entry: MacWidgetEntry

    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.small) {
            Label("MyApp", systemImage: "flag.checkered")
                .font(Theme.font.caption)
                .foregroundStyle(Theme.color.muted)

            elapsed
                .font(Theme.font.title)
                .monospacedDigit()
                .foregroundStyle(Theme.color.foreground)

            Text("\(entry.todayCount) today")
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(Theme.color.background, for: .widget)
    }

    @ViewBuilder
    private var elapsed: some View {
        if let startedAt = entry.sessionStartedAt {
            Text(
                timerInterval: startedAt...startedAt.addingTimeInterval(Self.maxSessionSeconds),
                countsDown: false
            )
        } else {
            Text("—")
        }
    }
}

#Preview("small", as: .systemSmall) {
    MacWidget()
} timeline: {
    MacWidgetEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-600), todayCount: 4)
}
