import Foundation

enum EmailAuthError: Error {
    case invalidEmail
    case alreadyUsed
    case server
}

enum EmailAuthService {

    private static let base = "https://semantic-feed.semantic-compression.workers.dev"

    static func registerEmail(
        userId: String,
        email: String
    ) async throws {
        guard let url = URL(string: "\(base)/registerEmail") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "userId": userId,
                "email": email,
            ]
        )

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else {
            throw EmailAuthError.server
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if http.statusCode == 400 || message.contains("invalid email") {
                throw EmailAuthError.invalidEmail
            }
            if http.statusCode == 409 || message.contains("unique") || message.contains("constraint") {
                throw EmailAuthError.alreadyUsed
            }
            throw EmailAuthError.server
        }
    }
}
