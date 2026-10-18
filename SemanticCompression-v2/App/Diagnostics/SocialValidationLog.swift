#if DEBUG
import CryptoKit
import Foundation
import UIKit

/// Opt-in evidence for real feed/APNs checks. Never records authentication tokens.
@MainActor
enum SocialValidationLog {
    private static var events: [[String: Any]] = []
    private static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--mim-live-validation")
    }
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MimSocialValidation", isDirectory: true)
    }
    static func record(_ name: String, _ values: [String: Any] = [:]) {
        guard enabled else { return }
        events.append(values.merging(["event": name, "at": Date().ISO8601Format()]) { _, new in new })
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["kind": "MimLiveSocialValidation", "events": events],
                options: [.sortedKeys, .prettyPrinted]).write(to: folder.appendingPathComponent("events.json"), options: .atomic)
        } catch { print("Live validation evidence could not be written.") }
    }
    static func tokenFingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func importSessionIfRequested() throws {
        guard enabled, ProcessInfo.processInfo.arguments.contains("--mim-use-validation-session") else { return }
        let url = folder.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard !AuthManager.shared.isAuthenticated,
              UserManager.shared.currentUser.id.isEmpty else {
            record("validationSessionSkipped", ["reason": "Existing account retained"])
            return
        }
        struct Session: Decodable {
            let user: AuthUser
            let accessToken: String
            let refreshToken: String
            let accessTokenExpiresAt: String
        }
        let session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var expiry = formatter.date(from: session.accessTokenExpiresAt)
        if expiry == nil {
            formatter.formatOptions = [.withInternetDateTime]
            expiry = formatter.date(from: session.accessTokenExpiresAt)
        }
        guard session.user.id.hasPrefix("mim-validation-"), let expiry, expiry > Date(),
              !session.accessToken.isEmpty, !session.refreshToken.isEmpty else {
            throw AuthError.invalidResponse
        }
        AuthManager.shared.applyValidationSession(.init(user: session.user,
            tokens: .init(accessToken: session.accessToken, refreshToken: session.refreshToken, accessTokenExpiresAt: expiry)))
        try FileManager.default.removeItem(at: url)
        record("validationSessionImported", ["userID": session.user.id])
    }
    static func snapshot() async {
        guard enabled else { return }
        record("applicationReady", ["version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "", "os": UIDevice.current.systemVersion,
            "isIPad": UIDevice.current.userInterfaceIdiom == .pad,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "generationSupported": CoreAIFluxAssets.runtimeSupported,
            "authenticated": AuthManager.shared.isAuthenticated,
            "pushEnvironment": PushEnvironment.current.rawValue,
            "notificationAuthorization": PushNotificationManager.shared.authorizationStatus.rawValue])
        do {
            let posts = try await FeedLoader.fetchPage(page: 0, pageSize: 40)
            var entries: [[String: Any]] = []
            for post in posts {
                var entry: [String: Any] = ["id": post.id, "name": post.displayName ?? "",
                    "avatarURL": post.avatarUrl ?? "", "hasImage": post.hasImage]
                if let recipe = post.recipe {
                    entry["family"] = recipe.model.family.rawValue
                    entry["recipeVersion"] = recipe.version
                    do { try recipe.validate(); entry["recipeValidated"] = true }
                    catch { entry["recipeValidated"] = false; entry["error"] = error.localizedDescription }
                }
                if let error = post.recipeReadError { entry["recipeValidated"] = false; entry["error"] = error }
                entries.append(entry)
            }
            record("liveFeedDecoded", ["postCount": entries.count, "posts": entries])
            if AuthManager.shared.isAuthenticated {
                let notifications = try await NotificationService.fetchNotifications()
                record("notificationsFetched", ["count": notifications.count,
                    "unreadCount": notifications.filter { !$0.isRead }.count])
            }
        } catch { record("snapshotFailed", ["error": error.localizedDescription]) }
    }
}
#endif
