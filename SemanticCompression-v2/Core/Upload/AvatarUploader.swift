//
//  AvatarUploader.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/14.
//


import Foundation

enum AvatarUploader {
    static func uploadAvatar(data: Data) async throws -> String {

        let base64 = data.base64EncodedString()
        let body = ["imageBase64": base64]

        guard let url = URL(string: "https://semantic-feed.semantic-compression.workers.dev/upload-avatar")
        else { throw URLError(.badURL) }

        var req = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)

        let result = try JSONDecoder().decode([String:String].self, from: data)
        guard let urlString = result["url"] else { throw URLError(.badServerResponse) }

        return urlString
    }
}
