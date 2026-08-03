import SwiftUI
import WidgetKit

@MainActor
struct HomeWidgetView: View {
    let entry: HomeWidgetEntry

    @Environment(\.widgetFamily) private var family

    private static let maxSessionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        content
            // Mandatory since the iOS 17 SDK: without it the system renders an
            // "adopt containerBackground" placeholder instead of the widget.
            // Accessory families supply their own vibrancy, so they take clear.
            .containerBackground(containerStyle, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text("MyApp · \(entry.todayCount) today")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            system
        }
    }

    private var containerStyle: Color {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            .clear
        default:
            Theme.color.background
        }
    }

    private var circular: some View {
        VStack(spacing: Theme.spacing.xxs) {
            Image(systemName: "flag.checkered")
            Text("\(entry.todayCount)")
                .font(Theme.font.label)
                .monospacedDigit()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
            Text("MyApp")
                .font(Theme.font.caption)
            elapsed
                .font(Theme.font.label)
                .monospacedDigit()
            Text("\(entry.todayCount) today")
                .font(Theme.font.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var system: some View {
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
