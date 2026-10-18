import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private var isOfflineReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-ui-review")
            || ProcessInfo.processInfo.arguments.contains("--mim-device-smoke")
        #else
        false
        #endif
    }
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if !isOfflineReview { PushNotificationManager.shared.configure() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard !isOfflineReview else { return }
        PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceTokenData: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard !isOfflineReview else { return }
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}
