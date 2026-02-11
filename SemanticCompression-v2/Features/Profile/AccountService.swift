//
//  AccountService.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//


import Foundation

enum AccountService {
    static func deleteAccount(userId: String, deleteToken: String) async throws {
        guard let url = URL(string: "https://semantic-feed.semantic-compression.workers.dev/deleteAccount")
        else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "userId": userId,
                "deleteToken": deleteToken
            ]
        )

        let (_, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
