//
//  UserService.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/15.
//


import Foundation

enum UserService {

    static func register(_ user: LocalUser) async {
        guard let url = URL(
            string: "https://semantic-feed.semantic-compression.workers.dev/registerUser"
        ) else { return }

        let payload: [String: Any] = [
            "id": user.id,
            "displayName": user.displayName,
            "avatarUrl": user.avatarUrl,
            "email": user.email ?? ""
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = try? JSONDecoder().decode(RegisterUserResponse.self, from: data),
               !response.deleteToken.isEmpty {
                var updated = UserManager.shared.currentUser
                if updated.deleteToken != response.deleteToken {
                    updated.deleteToken = response.deleteToken
                    UserManager.shared.saveUser(updated)
                }
            }
        } catch {
            #if DEBUG
            print("❌ registerUser failed:", error)
            #endif
        }
    }
}

private struct RegisterUserResponse: Decodable {
    let ok: Bool?
    let deleteToken: String
}
