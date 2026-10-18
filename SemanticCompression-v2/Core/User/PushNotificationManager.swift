import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String
    @Published var pendingPostID: String?
    @Published var pendingUserID: String?

    private static let tokenKey = "push_notification_device_token"
    private var languageSyncTask: Task<Void, Never>?
    private static let registrationLanguageKey = "push_notification_registered_language"

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
        #if DEBUG
        SocialValidationLog.record("notificationAuthorization", ["status": authorizationStatus.rawValue])
        #endif
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
        #if DEBUG
        SocialValidationLog.record("apnsTokenReceived", ["tokenSHA256": SocialValidationLog.tokenFingerprint(token),
            "environment": PushEnvironment.current.rawValue])
        #endif

        Task { await syncDeviceTokenIfPossible(force: true) }
    }

    func handleLanguageChanged() async {
        languageSyncTask?.cancel()
        languageSyncTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            await refreshAuthorizationStatus()
            await syncDeviceTokenIfPossible(force: true)
        }
        await languageSyncTask?.value
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("❌ APNs registration failed:", error)
        SocialValidationLog.record("apnsRegistrationFailed", ["error": error.localizedDescription])
        #endif
    }

    func notifyRemoteNotificationReceived() {
        NotificationCenter.default.post(name: .pushNotificationDidChange, object: nil)
    }

    func clearBadges() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func prepareForLogout() async {
        // The authenticated request must finish before AuthManager clears its tokens.
        await unregisterCurrentDeviceIfNeeded()
        clearBadges()
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
        let language = AppLanguage.resolve(UserDefaults.standard.string(forKey: AppPreferences.selectedLanguageKey)
            ?? AppLanguage.preferred.rawValue).rawValue
        let registeredLanguage = UserDefaults.standard.string(forKey: Self.registrationLanguageKey)
        guard force || registeredUserId != currentUserId || registeredLanguage != language else { return }

        do {
            try await PushNotificationService.registerDeviceToken(deviceToken, language: language)
            UserDefaults.standard.set(currentUserId, forKey: Self.registrationKey)
            UserDefaults.standard.set(language, forKey: Self.registrationLanguageKey)
            #if DEBUG
            SocialValidationLog.record("deviceRegistered", ["userID": currentUserId,
                "environment": PushEnvironment.current.rawValue, "language": language])
            #endif
        } catch {
            #if DEBUG
            print("❌ Device token sync failed:", error)
            SocialValidationLog.record("deviceRegistrationFailed", ["error": error.localizedDescription])
            #endif
        }
    }

    private func unregisterCurrentDeviceIfNeeded() async {
        let registeredUserId = UserDefaults.standard.string(forKey: Self.registrationKey) ?? ""
        guard !deviceToken.isEmpty, !registeredUserId.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.registrationKey)
            UserDefaults.standard.removeObject(forKey: Self.registrationLanguageKey)
            return
        }

        do {
            try await PushNotificationService.unregisterDeviceToken(deviceToken)
            #if DEBUG
            SocialValidationLog.record("deviceUnregistered", ["userID": registeredUserId])
            #endif
        } catch {
            #if DEBUG
            print("❌ Device token unregister failed:", error)
            #endif
        }

        UserDefaults.standard.removeObject(forKey: Self.registrationKey)
        UserDefaults.standard.removeObject(forKey: Self.registrationLanguageKey)
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        #if DEBUG
        let requestID = notification.request.identifier
        let type = notification.request.content.userInfo["type"] as? String ?? ""
        let postID = PostDestination.postID(from: notification.request.content.userInfo) ?? ""
        #endif
        Task { @MainActor in
            #if DEBUG
            SocialValidationLog.record("foregroundPushReceived", ["requestID": requestID,
                "type": type, "postID": postID])
            #endif
            self.notifyRemoteNotificationReceived()
            completionHandler([.banner, .list, .sound, .badge])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let shouldOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let postID = PostDestination.postID(from: response.notification.request.content.userInfo)
        let userID = PostDestination.followUserID(from: response.notification.request.content.userInfo)
        #if DEBUG
        let requestID = response.notification.request.identifier
        let type = response.notification.request.content.userInfo["type"] as? String ?? ""
        #endif
        Task { @MainActor in
            if shouldOpen {
                #if DEBUG
                SocialValidationLog.record("pushOpened", ["requestID": requestID,
                    "type": type, "postID": postID ?? "", "userID": userID ?? "",
                    "completionOnMainThread": Thread.isMainThread])
                #endif
                self.pendingPostID = userID == nil ? postID : nil
                self.pendingUserID = userID
                self.notifyRemoteNotificationReceived()
            }
            // UIKit resumes and snapshots the scene from this callback. The async
            // delegate bridge can invoke it on a worker thread after MainActor.run.
            completionHandler()
        }
    }
}

extension Notification.Name {
    static let pushNotificationDidChange = Notification.Name("pushNotificationDidChange")
}
