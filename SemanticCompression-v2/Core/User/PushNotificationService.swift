import Foundation

enum PushNotificationService {
    static func registerDeviceToken(_ token: String) async throws {
        guard let url = URL(string: FeedAPI.base + "/devices/register") else {
            throw URLError(.badURL)
        }

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "deviceToken": token,
            "platform": "ios"
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func unregisterDeviceToken(_ token: String) async throws {
        guard let url = URL(string: FeedAPI.base + "/devices/unregister") else {
            throw URLError(.badURL)
        }

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "deviceToken": token,
            "platform": "ios"
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
