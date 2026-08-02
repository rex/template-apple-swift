import ActivityKit
import SwiftUI
import WidgetKit

@MainActor
struct SessionLiveActivity: Widget {
    /// System-imposed slot widths, not design tokens: the Dynamic Island
    /// clamps these regions and an unframed `.timer` is truncated inside them.
    private static let expandedTimerWidth: CGFloat = 64
    private static let compactTimerWidth: CGFloat = 44

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(state: context.state, name: context.attributes.sessionName)
                .activityBackgroundTint(Theme.color.surface)
                .activitySystemActionForegroundColor(Theme.color.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.count)", systemImage: "flag.checkered")
                        .font(Theme.font.label)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(Theme.font.label)
                        .monospacedDigit()
                        .frame(maxWidth: Self.expandedTimerWidth)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.sessionName)
                        .font(Theme.font.caption)
                        .foregroundStyle(Theme.color.muted)
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: Self.compactTimerWidth)
            } minimal: {
                Image(systemName: "flag.checkered")
            }
            .keylineTint(Theme.color.accent)
        }
        // iOS 18+: projects this activity onto the paired Apple Watch, which is
        // why the watch app does not re-render the same session itself.
        .supplementalActivityFamilies([.small])
    }
}

@MainActor
struct LockScreenView: View {
    let state: SessionActivityAttributes.ContentState
    let name: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing.medium) {
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                Text(name)
                    .font(Theme.font.caption)
                    .foregroundStyle(Theme.color.muted)

                // Self-advancing without any `Activity.update`, which is why
                // the host only pushes state on lifecycle changes.
                Text(state.startedAt, style: .timer)
                    .font(Theme.font.title)
                    .monospacedDigit()
                    .foregroundStyle(Theme.color.foreground)
            }

            Spacer(minLength: Theme.spacing.small)

            Label("\(state.count)", systemImage: "flag.checkered")
                .font(Theme.font.headline)
                .foregroundStyle(Theme.color.accent)
        }
        .padding(Theme.spacing.medium)
    }
}

#Preview("lock screen", as: .content, using: SessionActivityAttributes(sessionName: "MyApp")) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-600), count: 4)
}
