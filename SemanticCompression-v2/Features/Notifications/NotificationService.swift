import Foundation

enum NotificationService {
    static func fetchNotifications(limit: Int = 40) async throws -> [AppNotification] {
        guard var components = URLComponents(string: FeedAPI.base + "/notifications") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = try await AuthManager.shared.authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AppNotification].self, from: data)
    }

    static func markAllAsRead() async throws {
        guard let url = URL(string: FeedAPI.base + "/notifications/read-all") else {
            throw URLError(.badURL)
        }

        let request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
