//
//  ReportService.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/15.
//


import Foundation

enum ReportService {

    static func submit(
        postId: String,
        reason: String
    ) async throws {

        guard let url = URL(
            string: "https://semantic-feed.semantic-compression.workers.dev/report"
        ) else { throw URLError(.badURL) }

        let payload: [String: Any] = [
            "postId": postId,
            "reason": reason
        ]

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
