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

enum FollowListKind {
    case followers
    case following

    var endpoints: [String] {
        switch self {
        case .followers:
            return ["/getFollowers", "/followers"]
        case .following:
            return ["/getFollowing", "/following"]
        }
    }
}

struct FollowListUser: Decodable, Identifiable {
    let id: String
    let displayName: String
    let avatarUrl: String
    let bio: String?
    let isFollowing: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarUrl
        case bio
        case isFollowing
    }

    init(
        id: String,
        displayName: String,
        avatarUrl: String,
        bio: String?,
        isFollowing: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.isFollowing = isFollowing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl) ?? ""
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? false
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

    static func fetchUsers(kind: FollowListKind) async throws -> [FollowListUser] {
        let currentUserID = UserManager.shared.currentUser.id
        let queryVariants: [[URLQueryItem]] = [
            currentUserID.isEmpty ? [] : [URLQueryItem(name: "userId", value: currentUserID)],
            []
        ]

        for endpoint in kind.endpoints {
            for queryItems in queryVariants {
                guard var components = URLComponents(string: base + endpoint) else {
                    continue
                }
                if !queryItems.isEmpty {
                    components.queryItems = queryItems
                }
                guard let url = components.url else { continue }

                do {
                    let request = try await AuthManager.shared.authorizedRequest(url: url)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continue
                    }

                    if let users = try decodeFollowUsers(from: data, kind: kind), !users.isEmpty {
                        return users
                    }

                    if let users = try await decodeUsersViaUserIDs(from: data, kind: kind), !users.isEmpty {
                        return users
                    }

                    if let users = try decodeFollowUsers(from: data, kind: kind) {
                        return users
                    }
                } catch {
                    continue
                }
            }
        }

        throw URLError(.badServerResponse)
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

private extension FollowService {
    struct FollowUserIDRow: Decodable {
        let id: String?
        let userId: String?
        let followedUserId: String?
        let followerUserId: String?
    }

    struct FollowUsersEnvelope: Decodable {
        let users: [FollowListUser]?
        let followers: [FollowListUser]?
        let following: [FollowListUser]?
    }

    struct FollowUserIDsEnvelope: Decodable {
        let users: [String]?
        let followers: [String]?
        let following: [String]?
    }

    static func decodeFollowUsers(from data: Data, kind: FollowListKind) throws -> [FollowListUser]? {
        let decoder = JSONDecoder()

        if let users = try? decoder.decode([FollowListUser].self, from: data) {
            return users
        }

        if let envelope = try? decoder.decode(FollowUsersEnvelope.self, from: data) {
            switch kind {
            case .followers:
                return envelope.followers ?? envelope.users
            case .following:
                return envelope.following ?? envelope.users
            }
        }

        return nil
    }

    static func decodeUsersViaUserIDs(from data: Data, kind: FollowListKind) async throws -> [FollowListUser]? {
        let decoder = JSONDecoder()
        let ids: [String]?

        if let directIDs = try? decoder.decode([String].self, from: data) {
            ids = directIDs
        } else if let envelope = try? decoder.decode(FollowUserIDsEnvelope.self, from: data) {
            switch kind {
            case .followers:
                ids = envelope.followers ?? envelope.users
            case .following:
                ids = envelope.following ?? envelope.users
            }
        } else if let rows = try? decoder.decode([FollowUserIDRow].self, from: data) {
            ids = rows.compactMap {
                $0.id ?? $0.userId ?? $0.followedUserId ?? $0.followerUserId
            }
        } else {
            ids = nil
        }

        guard let ids else { return nil }
        if ids.isEmpty { return [] }

        var users: [FollowListUser] = []
        users.reserveCapacity(ids.count)
        for id in ids {
            do {
                let profile = try await fetchPublicProfile(userId: id)
                users.append(
                    FollowListUser(
                        id: profile.id,
                        displayName: profile.displayName,
                        avatarUrl: profile.avatarUrl,
                        bio: profile.bio,
                        isFollowing: profile.isFollowing
                    )
                )
            } catch {
                continue
            }
        }
        return users
    }
}
