import Foundation

enum FollowServiceError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

enum FollowService {
    private static let base = FeedAPI.base

    static func follow(userId: String) async throws {
        try await send(endpoint: "/followUser", payload: ["followedUserId": userId])
    }

    static func unfollow(userId: String) async throws {
        try await send(endpoint: "/unfollowUser", payload: ["followedUserId": userId])
    }

    static func fetchPublicProfile(userId: String) async throws -> PublicUserProfile {
        guard var components = URLComponents(string: base + "/getUser") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "id", value: userId)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        if let token = try? await AuthManager.shared.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PublicUserProfile.self, from: data)
    }

    private static func send(endpoint: String, payload: [String: String]) async throws {
        guard let url = URL(string: base + endpoint) else {
            throw URLError(.badURL)
        }

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(FollowErrorResponse.self, from: data))?.error
            throw FollowServiceError.server(message ?? "Request failed")
        }
    }
}

private struct FollowErrorResponse: Decodable {
    let error: String?
}
