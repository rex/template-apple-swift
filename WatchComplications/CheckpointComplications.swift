import SwiftUI
import WidgetKit

@MainActor
struct SessionComplication: Widget {
    static let kind = "SessionComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            SessionComplicationView(entry: entry)
        }
        .configurationDisplayName("Session")
        .description("How long the current MyApp session has been running.")
        // `accessoryCorner` is watchOS-only; it is legal here because nothing
        // in this directory is ever compiled for iOS or macOS.
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

@MainActor
struct TodayCountComplication: Widget {
    static let kind = "TodayCountComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            TodayCountComplicationView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Checkpoints logged today.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

@MainActor
struct SessionComplicationView: View {
    let entry: ComplicationEntry

    @Environment(\.widgetFamily) private var family

    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        content
            // Mandatory on every widget view. Complication chrome supplies its
            // own vibrancy, so the container itself stays clear.
            .containerBackground(Color.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            elapsed
        case .accessoryCorner:
            Image(systemName: "flag.checkered")
                .widgetLabel { elapsed }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                Text("MyApp")
                    .font(Theme.font.caption)
                elapsed
                    .font(Theme.font.label)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: Theme.spacing.xxs) {
                Image(systemName: "flag.checkered")
                elapsed
                    .font(Theme.font.caption)
                    .monospacedDigit()
            }
        }
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

@MainActor
struct TodayCountComplicationView: View {
    let entry: ComplicationEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(Color.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.todayCount) today")
        case .accessoryCorner:
            Image(systemName: "flag.checkered")
                .widgetLabel { Text("\(entry.todayCount) today") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                Text("MyApp")
                    .font(Theme.font.caption)
                Text("\(entry.todayCount) today")
                    .font(Theme.font.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: Theme.spacing.xxs) {
                Image(systemName: "flag.checkered")
                Text("\(entry.todayCount)")
                    .font(Theme.font.label)
                    .monospacedDigit()
            }
        }
    }
}

#Preview("circular", as: .accessoryCircular) {
    SessionComplication()
} timeline: {
    ComplicationEntry(date: .now, sessionStartedAt: .now.addingTimeInterval(-600), todayCount: 4)
}

#Preview("rectangular", as: .accessoryRectangular) {
    TodayCountComplication()
} timeline: {
    ComplicationEntry(date: .now, sessionStartedAt: nil, todayCount: 4)
}
