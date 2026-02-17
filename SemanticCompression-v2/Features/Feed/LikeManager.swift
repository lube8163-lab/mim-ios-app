//
//  LikeManager.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/10.
//


import Foundation

final class LikeManager {
    static let shared = LikeManager()
    private init() {}

    func toggleLike(for post: Post) {
        guard !UserManager.shared.currentUser.id.isEmpty else { return }
        if (post.isLikedByCurrentUser ?? false) {
            unlike(post)
        } else {
            like(post)
        }
    }

    private func like(_ post: Post) {
        post.isLikedByCurrentUser = true
        post.likeCount = (post.likeCount ?? 0) + 1

        Task { await sendLikeToServer(post.id) }
    }

    private func unlike(_ post: Post) {
        post.isLikedByCurrentUser = false
        post.likeCount = max(0, (post.likeCount ?? 0) - 1)

        Task { await sendUnlikeToServer(post.id) }
    }

    private func sendLikeToServer(_ postId: String) async {
        await sendToServer(endpoint: "like", postId: postId)
    }

    private func sendUnlikeToServer(_ postId: String) async {
        await sendToServer(endpoint: "unlike", postId: postId)
    }

    private func sendToServer(endpoint: String, postId: String) async {
        guard let url = URL(string: "https://semantic-feed.semantic-compression.workers.dev/\(endpoint)") else { return }
        do {
            let body = ["postId": postId]
            var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            #if DEBUG
            print("📤 Sending to server:", url.absoluteString, body)
            #endif

            let (_, response) = try await URLSession.shared.data(for: request)
            #if DEBUG
            print("✅ Server response:", response)
            #endif
        } catch {
            #if DEBUG
            print("❌ Network error:", error)
            #endif
        }
    }
}
