import Foundation
#if os(iOS)
import ActivityKit

/// Owned wholly by the `live-activity` component.
///
/// `#if os(iOS)` rather than `#if canImport(ActivityKit)`: the module resolves
/// on macOS and Mac Catalyst builds where the types are unavailable.
///
/// Every ActivityKit call happens inside a DETACHED task on purpose.
/// `Activity`'s async methods (`update`, `end`) run on the global executor, so
/// calling one with an `Activity` reference held by the main-actor region is a
/// `sending` violation under region isolation ("sending 'current' risks
/// causing data races"). The detached closures capture only Sendable values
/// (content, dismissal policy) and fetch `Activity` references from
/// `Activity.activities` inside their own disconnected region, so nothing
/// non-Sendable ever crosses an isolation boundary. Reading the token stream
/// is different: it never sends the activity, so `observePushToken` may hold
/// one.
@MainActor
public final class LiveActivityController {
    public static let shared = LiveActivityController()

    /// Shown as the activity's name on the Lock Screen.
    public static let defaultSessionName = "MyApp"

    /// A Live Activity older than this is stale; the system dims it rather than
    /// showing a timer that has silently stopped tracking reality.
    private static let staleAfter: TimeInterval = 8 * 60 * 60

    private init() {}

    /// `nonisolated`: `Activity.activities` is nonisolated static state. A
    /// main-actor accessor would drag its result into the main-actor region,
    /// which is exactly what makes the later `update`/`end` calls illegal.
    private nonisolated static var hasActive: Bool {
        !Activity<SessionActivityAttributes>.activities.isEmpty
    }

    /// The store seam: one idempotent call that starts, updates or ends the
    /// activity from whatever the store now holds. `CheckpointStore`'s
    /// `live-activity` marker block calls this on every mutation.
    public func sync(session: SessionState, todayCount: Int) {
        guard let startedAt = session.startedAt else {
            endAll()
            return
        }
        let state = SessionActivityAttributes.ContentState(startedAt: startedAt, count: todayCount)
        if Self.hasActive {
            update(state)
        } else {
            start(sessionName: Self.defaultSessionName, state: state)
        }
    }

    /// Idempotent. Returns false when the user has disabled Live Activities.
    @discardableResult
    public func start(
        sessionName: String,
        state: SessionActivityAttributes.ContentState
    ) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
        if Self.hasActive {
            Self.pushUpdate(content)
            return true
        }
        do {
            let activity = try Activity.request(
                attributes: SessionActivityAttributes(sessionName: sessionName),
                content: content,
                pushType: nil
            )
            observePushToken(for: activity)
            return true
        } catch {
            return false          // the app still works; only the Lock Screen surface is missing
        }
    }

    public func update(_ state: SessionActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
        Self.pushUpdate(content)
    }

    public func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) {
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
        }
    }

    /// Fire-and-forget update. The activity is fetched inside the detached
    /// task and no-ops when none is running, which also makes callers'
    /// guard-then-update races harmless.
    private nonisolated static func pushUpdate(
        _ content: ActivityContent<SessionActivityAttributes.ContentState>
    ) {
        Task.detached {
            await Activity<SessionActivityAttributes>.activities.first?.update(content)
        }
    }

    /// Push-token seam, deliberately inert in v1.
    ///
    /// `pushTokenUpdates` terminates when the activity ends, so this loop needs
    /// no cancellation timer. To drive activities from a server, pass
    /// `pushType: .token` in `start`, forward this token, and additionally
    /// observe the static `Activity.pushToStartTokenUpdates` — that is the only
    /// way to *start* an activity from a push. `PushType.channel(_:)` is the
    /// broadcast alternative for fanning one update out to many devices.
    private func observePushToken(for activity: Activity<SessionActivityAttributes>) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                _ = tokenData     // a registrar lands here alongside the `nse` component
            }
        }
    }
}
#endif
