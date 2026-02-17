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
    let email: String?
}

struct AuthSessionPayload {
    let user: AuthUser
    let tokens: AuthTokens
}

enum AuthService {
    private static let base = "https://semantic-feed.semantic-compression.workers.dev"

    static func startOtp(email: String) async throws {
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
    }

    static func verifyOtp(email: String, otp: String, deviceName: String) async throws -> AuthSessionPayload {
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

private struct VerifyResponse: Decodable {
    let ok: Bool
    let user: AuthUser
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
}

private struct RefreshResponse: Decodable {
    let ok: Bool
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
}
