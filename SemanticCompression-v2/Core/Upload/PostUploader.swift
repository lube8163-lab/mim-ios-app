//
//  PostUploadPayload.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/09.
//

import Foundation

// ======================================================
//  Cloudflare Worker `/post` に合わせた送信フォーマット
// ======================================================
struct PostUploadPayload: Codable {
    let id: String

    // --- 投稿内容 ---
    let mode: Int
    let payload: PostPayload?
    let tags: [String]
    let userText: String?
    let hasImage: Bool

    // ISO8601 文字列
    let createdAt: String
}


// ======================================================
//  アップロードロジック
// ======================================================
final class PostUploader {

    private let endpoint = "https://semantic-feed.semantic-compression.workers.dev/post"

    func upload(post: Post) async throws {
        // 🔹 Worker のフィールドに完全対応した payload
        let payload = PostUploadPayload(
            id: post.id,
            mode: post.mode,
            payload: post.payload,
            tags: post.tags,
            userText: post.userText,
            hasImage: post.hasImage,

            createdAt: ISO8601DateFormatter().string(from: post.createdAt)
        )

        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // 🔹 JSON へエンコード
        let jsonData = try JSONEncoder().encode(payload)
        request.httpBody = jsonData

        // 🔹 POST 実行
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            #if DEBUG
            print("❌ Server returned:", (response as? HTTPURLResponse)?.statusCode ?? -1)
            #endif
            throw URLError(.badServerResponse)
        }
        
        #if DEBUG
        print("✅ Post uploaded to server: \(post.id)")
        #endif
    }
}
