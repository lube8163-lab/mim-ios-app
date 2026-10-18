//
//  UserService.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/15.
//


import Foundation

@MainActor
enum UserService {

    static func register(_ user: LocalUser) async {
        do {
            let registered = try await registerChecked(user)
            if UserManager.shared.currentUser.id == user.id,
               UserManager.shared.currentUser.deleteToken != registered.deleteToken {
                var current = UserManager.shared.currentUser
                current.deleteToken = registered.deleteToken
                UserManager.shared.saveUser(current)
            }
        }
        catch {
            #if DEBUG
            print("registerUser failed:", error)
            #endif
        }
    }

    static func registerChecked(_ user: LocalUser) async throws -> LocalUser {
        guard !user.id.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let policy = try ContentSafetyPolicy.bundled()
        try policy.validate(user.displayName)
        try policy.validate(user.bio)
        guard user.displayName.utf16.count <= 80, user.bio.utf16.count <= 120 else { throw ContentSafetyError.tooLong }
        guard let url = URL(
            string: "https://semantic-feed.semantic-compression.workers.dev/registerUser"
        ) else { throw URLError(.badURL) }

        let payload: [String: Any] = [
            "displayName": user.displayName,
            "avatarUrl": user.avatarUrl,
            "bio": user.bio
        ]

            var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, httpResponse) = try await URLSession.shared.data(for: request)
            guard let http = httpResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let response = try JSONDecoder().decode(RegisterUserResponse.self, from: data)
            guard response.ok == true else { throw URLError(.badServerResponse) }
            var registered = user
            if let token = response.deleteToken, !token.isEmpty { registered.deleteToken = token }
            return registered
    }
}

private struct RegisterUserResponse: Decodable {
    let ok: Bool?
    let deleteToken: String?
}
