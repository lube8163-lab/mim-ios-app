//
//  AvatarUploader.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/14.
//


import Foundation
import UIKit

@MainActor
enum AvatarUploader {
    static func uploadAvatar(data: Data) async throws -> String {
        return try await CheckedMedia.send(data, check: { bytes in
            guard let image = UIImage(data: bytes) else { throw URLError(.cannotDecodeContentData) }
            try await ImageSafetyService.check(image)
        }, send: { checked in
        let base64 = checked.base64EncodedString()
        let body = ["imageBase64": base64]

        guard let url = URL(string: "https://semantic-feed.semantic-compression.workers.dev/upload-avatar")
        else { throw URLError(.badURL) }

        var req = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode([String:String].self, from: data)
        guard let urlString = result["url"] else { throw URLError(.badServerResponse) }

        guard URL(string: urlString)?.scheme == "https" else { throw URLError(.badServerResponse) }
        return urlString
        })
    }
}
