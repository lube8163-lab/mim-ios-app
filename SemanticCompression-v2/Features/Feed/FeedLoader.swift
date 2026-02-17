//
//  FeedLoader.swift
//  SemanticCompressionApp
//

import Foundation

/// Cloudflare Worker API ベースURL
enum FeedAPI {
    static let base = "https://semantic-feed.semantic-compression.workers.dev"
}

struct FeedLoader {

    static func fetchPage(page: Int, pageSize: Int = 10) async throws -> [Post] {
        try await fetch(
            path: "/feed",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(pageSize)),
                URLQueryItem(name: "userId", value: UserManager.shared.currentUser.id),
            ]
        )
    }

    static func fetchMyPosts(
        userId: String,
        page: Int,
        pageSize: Int = 10
    ) async throws -> [Post] {
        try await fetch(
            path: "/posts",
            queryItems: [
                URLQueryItem(name: "userId", value: userId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(pageSize)),
                URLQueryItem(name: "viewerId", value: UserManager.shared.currentUser.id),
            ]
        )
    }

    static func fetchLikedPosts(
        userId: String,
        page: Int,
        pageSize: Int = 10
    ) async throws -> [Post] {
        try await fetch(
            path: "/likes",
            queryItems: [
                URLQueryItem(name: "userId", value: userId),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(pageSize)),
                URLQueryItem(name: "viewerId", value: UserManager.shared.currentUser.id),
            ]
        )
    }

    private static func fetch(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> [Post] {
        guard var components = URLComponents(string: FeedAPI.base + path) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        #if DEBUG
        print("📡 Fetching feed from:", url.absoluteString)
        #endif

        var request = URLRequest(url: url)
        if let token = try? await AuthManager.shared.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse,
            !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "FeedLoader",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode) for \(path)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let decoded = try decoder.decode([Post].self, from: data)
            let resolved = decoded.map { PostStore.shared.resolve($0) }
            #if DEBUG
            print("📥 Loaded \(resolved.count) posts")
            #endif
            return resolved
        } catch {
            #if DEBUG
            print("❌ JSON decode error:", error)
            print("❌ Response JSON:", String(data: data, encoding: .utf8) ?? "nil")
            #endif
            throw error
        }
    }
}
