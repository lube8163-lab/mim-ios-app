import Foundation

enum BlockService {

    private static let base = "https://semantic-feed.semantic-compression.workers.dev"

    static func fetchBlockedUsers() async throws -> [String] {
        guard let url = URL(string: "\(base)/blockedUsers") else {
            throw URLError(.badURL)
        }

        let req = try await AuthManager.shared.authorizedRequest(url: url)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids
        }

        struct Row: Decodable { let blockedUserId: String }
        if let rows = try? JSONDecoder().decode([Row].self, from: data) {
            return rows.map { $0.blockedUserId }
        }

        return []
    }

    static func block(
        blockedUserId: String
    ) async throws {
        try await send(
            endpoint: "/blockUser",
            payload: [
                "blockedUserId": blockedUserId,
            ]
        )
    }

    static func unblock(
        blockedUserId: String
    ) async throws {
        try await send(
            endpoint: "/unblockUser",
            payload: [
                "blockedUserId": blockedUserId,
            ]
        )
    }

    static func fetchDisplayName(
        userId: String
    ) async throws -> String? {
        guard let url = URL(string: "\(base)/getUser?id=\(userId)") else {
            throw URLError(.badURL)
        }

        let (data, res) = try await URLSession.shared.data(from: url)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct UserRow: Decodable {
            let displayName: String?
        }
        let decoded = try? JSONDecoder().decode(UserRow.self, from: data)
        return decoded?.displayName
    }

    private static func send(
        endpoint: String,
        payload: [String: String]
    ) async throws {
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw URLError(.badURL)
        }

        var req = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
