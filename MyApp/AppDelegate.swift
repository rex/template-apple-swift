import UIKit
import UserNotifications
import os

/// Owned wholly by the `nse` component: with no Notification Service Extension
/// there is nothing for a remote notification to do, so there is no delegate.
///
/// `@MainActor` is explicit even though `UIApplicationDelegate` is already
/// main-actor isolated in the SDK — this template never lets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` decide a type's isolation.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: "com.example.myapp", category: "push")

    /// Called from `MyAppApp`'s `nse` marker block. APNs only mints a token for
    /// alert pushes once the user has authorized them, so authorization comes
    /// first and a denial short-circuits registration.
    func registerForRemoteNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            guard granted else {
                Self.logger.notice("Notification authorization denied; not registering with APNs")
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // The token is a stable per-install identifier, so it is never logged
        // (.claude/rules/security.md). Byte count is enough to prove the round
        // trip worked; read the real value from the device console if you must.
        Self.logger.info("APNs registration succeeded (\(deviceToken.count, privacy: .public) bytes)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Background delivery path for `content-available` pushes. Apple budgets
    /// those at roughly 2–3 per hour per device, which is why the refresh that
    /// actually matters happens in the Notification Service Extension on a
    /// visible alert instead of here.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        .noData
    }
}
