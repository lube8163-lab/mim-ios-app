import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String

    private static let tokenKey = "push_notification_device_token"
    private static let registrationKey = "push_notification_registered_user_id"

    private override init() {
        deviceToken = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func handleAuthenticationStateChanged(isAuthenticated: Bool) async {
        await refreshAuthorizationStatus()

        if !isAuthenticated {
            await unregisterCurrentDeviceIfNeeded()
            return
        }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        UIApplication.shared.registerForRemoteNotifications()
        await syncDeviceTokenIfPossible(force: false)
    }

    func didRegisterForRemoteNotifications(deviceTokenData: Data) {
        let token = deviceTokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        UserDefaults.standard.set(token, forKey: Self.tokenKey)

        Task { await syncDeviceTokenIfPossible(force: true) }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("❌ APNs registration failed:", error)
        #endif
    }

    func notifyRemoteNotificationReceived() {
        NotificationCenter.default.post(name: .pushNotificationDidChange, object: nil)
    }

    func clearBadges() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func setBadgeCount(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
        if count <= 0 {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                await refreshAuthorizationStatus()
                return granted
            } catch {
                #if DEBUG
                print("❌ Notification authorization failed:", error)
                #endif
                return false
            }
        @unknown default:
            return false
        }
    }

    private func syncDeviceTokenIfPossible(force: Bool) async {
        guard AuthManager.shared.isAuthenticated else { return }
        guard !deviceToken.isEmpty else { return }
        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral else { return }

        let currentUserId = UserManager.shared.currentUser.id
        let registeredUserId = UserDefaults.standard.string(forKey: Self.registrationKey) ?? ""
        guard force || registeredUserId != currentUserId else { return }

        do {
            try await PushNotificationService.registerDeviceToken(deviceToken)
            UserDefaults.standard.set(currentUserId, forKey: Self.registrationKey)
        } catch {
            #if DEBUG
            print("❌ Device token sync failed:", error)
            #endif
        }
    }

    private func unregisterCurrentDeviceIfNeeded() async {
        let registeredUserId = UserDefaults.standard.string(forKey: Self.registrationKey) ?? ""
        guard !deviceToken.isEmpty, !registeredUserId.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.registrationKey)
            return
        }

        do {
            try await PushNotificationService.unregisterDeviceToken(deviceToken)
        } catch {
            #if DEBUG
            print("❌ Device token unregister failed:", error)
            #endif
        }

        UserDefaults.standard.removeObject(forKey: Self.registrationKey)
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            self.notifyRemoteNotificationReceived()
        }
        return [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            self.notifyRemoteNotificationReceived()
        }
    }
}

extension Notification.Name {
    static let pushNotificationDidChange = Notification.Name("pushNotificationDidChange")
}
