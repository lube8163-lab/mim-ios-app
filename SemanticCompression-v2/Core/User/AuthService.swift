import Foundation

enum AuthError: Error {
    case badURL
    case invalidEmail
    case server(String)
    case unauthorized
    case invalidResponse
}

struct AuthUser: Decodable {
    let id: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let email: String?
}

struct AuthSessionPayload {
    let user: AuthUser
    let tokens: AuthTokens
}

struct OtpStartPayload {
    let challengeId: String
}

struct AppleSignInFullName: Encodable {
    let givenName: String?
    let familyName: String?
    let nickname: String?

    init?(_ components: PersonNameComponents?) {
        let givenName = components?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyName = components?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = components?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard [givenName, familyName, nickname].contains(where: { ($0 ?? "").isEmpty == false }) else {
            return nil
        }

        self.givenName = givenName?.isEmpty == false ? givenName : nil
        self.familyName = familyName?.isEmpty == false ? familyName : nil
        self.nickname = nickname?.isEmpty == false ? nickname : nil
    }
}

enum AuthService {
    private static let base = "https://semantic-feed.semantic-compression.workers.dev"

    static func startOtp(email: String) async throws -> OtpStartPayload {
        guard let url = URL(string: "\(base)/auth/start") else {
            throw AuthError.badURL
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            throw AuthError.invalidEmail
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": normalized])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 400 { throw AuthError.invalidEmail }
            let message = String(data: data, encoding: .utf8) ?? "Failed to start OTP"
            throw AuthError.server(message)
        }

        let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
        return OtpStartPayload(challengeId: decoded.challengeId)
    }

    static func verifyOtp(
        email: String,
        challengeId: String,
        otp: String,
        deviceName: String
    ) async throws -> AuthSessionPayload {
        guard let url = URL(string: "\(base)/auth/verify") else {
            throw AuthError.badURL
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = otp.trimmingCharacters(in: .whitespacesAndNewlines)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": normalized,
            "challengeId": challengeId,
            "otp": code,
            "deviceName": deviceName
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw AuthError.unauthorized }
            let message = String(data: data, encoding: .utf8) ?? "Failed to verify OTP"
            throw AuthError.server(message)
        }

        let decoded = try JSONDecoder().decode(VerifyResponse.self, from: data)
        return sessionPayload(from: decoded)
    }

    static func signInWithApple(
        identityToken: String,
        nonce: String,
        fullName: AppleSignInFullName?,
        authorizationCode: String?,
        deviceName: String
    ) async throws -> AuthSessionPayload {
        guard let url = URL(string: "\(base)/auth/apple") else {
            throw AuthError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            AppleSignInRequest(
                identityToken: identityToken,
                nonce: nonce,
                fullName: fullName,
                authorizationCode: authorizationCode,
                deviceName: deviceName
            )
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw AuthError.unauthorized }
            let message = String(data: data, encoding: .utf8) ?? "Failed to sign in with Apple"
            throw AuthError.server(message)
        }

        let decoded = try JSONDecoder().decode(VerifyResponse.self, from: data)
        return sessionPayload(from: decoded)
    }

    private static func sessionPayload(from decoded: VerifyResponse) -> AuthSessionPayload {
        let tokens = AuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(decoded.accessTokenExpiresIn))
        )
        return AuthSessionPayload(user: decoded.user, tokens: tokens)
    }

    static func refresh(refreshToken: String) async throws -> AuthTokens {
        guard let url = URL(string: "\(base)/auth/refresh") else {
            throw AuthError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw AuthError.unauthorized }
            let message = String(data: data, encoding: .utf8) ?? "Failed to refresh"
            throw AuthError.server(message)
        }

        let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
        return AuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(decoded.accessTokenExpiresIn))
        )
    }

    static func logout(accessToken: String?, refreshToken: String?, allDevices: Bool) async {
        guard let url = URL(string: "\(base)/auth/logout") else { return }

        var payload: [String: Any] = ["allDevices": allDevices]
        if let refreshToken, !refreshToken.isEmpty {
            payload["refreshToken"] = refreshToken
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken, !accessToken.isEmpty {
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: req)
    }
}

private struct StartResponse: Decodable {
    let ok: Bool
    let challengeId: String
}

private struct VerifyResponse: Decodable {
    let ok: Bool
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
}

private struct AppleSignInRequest: Encodable {
    let identityToken: String
    let nonce: String
    let fullName: AppleSignInFullName?
    let authorizationCode: String?
    let deviceName: String
}

private struct RefreshResponse: Decodable {
    let ok: Bool
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
}
