import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif
import os

/// Why this extension exists at all:
///
/// Apple budgets silent (`content-available`) pushes at roughly 2–3 per hour
/// per device and drops the rest without telling you. A push that carries a
/// *visible* alert has no such budget, and `mutable-content: 1` routes it here
/// first — so mirroring state into the App Group from a Notification Service
/// Extension is the reliable way to keep widgets fresh from a server. That
/// trade (one visible notification per refresh) is the whole design.
///
/// On an iOS 26 floor, delete this component and adopt `WidgetPushHandler` /
/// `WidgetCenter.shared.currentPushInfo` instead: the widget extension
/// registers its own APNs token and refreshes with no host app, no extension
/// hop, and no visible alert.
///
/// `nonisolated` (never `@MainActor`): both overrides are nonisolated in the
/// superclass, and a main-actor override cannot override a nonisolated one.
nonisolated final class NotificationService: UNNotificationServiceExtension {
    private static let logger = Logger(
        subsystem: "com.example.myapp.notificationservice",
        category: "NSE"
    )

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent

        // Deliver whatever happens below. A notification that never fires its
        // handler is shown unmodified after a ~30 s stall.
        defer { contentHandler(bestAttempt ?? request.content) }

        let userInfo = request.content.userInfo
        // iOS only routes a push here when `aps.mutable-content == 1`, but
        // asserting it keeps the App Group write provably scoped.
        guard Self.isMutableContent(userInfo) else { return }

        let started = (userInfo["sessionStartedAt"] as? Double).flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        }
        let today = userInfo["todayCount"] as? Int ?? 0

        WidgetSync.write(
            WidgetSnapshot(sessionStartedAt: started, todayCount: today, lastUpdatedAt: .now)
        )
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        Self.logger.info("Mirrored push payload into the App Group and reloaded widget timelines")
    }

    override func serviceExtensionTimeWillExpire() {
        // The `defer` above has normally already fired; this is the safety net
        // Apple's template requires for the path where it has not.
        if let bestAttempt {
            contentHandler?(bestAttempt)
        }
    }

    private static func isMutableContent(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let aps = userInfo["aps"] as? [AnyHashable: Any] else { return false }
        switch aps["mutable-content"] {
        case let value as Int: return value == 1
        case let value as NSNumber: return value.intValue == 1
        case let value as Bool: return value
        default: return false
        }
    }
}
