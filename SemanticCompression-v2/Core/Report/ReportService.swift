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
        reason: String,
        reporterUserId: String
    ) async {

        guard let url = URL(
            string: "https://semantic-feed.semantic-compression.workers.dev/report"
        ) else {
            #if DEBUG
            print("❌ invalid URL")
            #endif
            return
        }

        let payload: [String: Any] = [
            "postId": postId,
            "reason": reason,
            "reporterUserId": reporterUserId
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                #if DEBUG
                print("📡 Report response:", http.statusCode)
                #endif
            }
        } catch {
            #if DEBUG
            print("❌ Report failed:", error)
            #endif
        }
    }
}
