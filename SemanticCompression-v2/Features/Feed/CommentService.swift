import Foundation

enum CommentService {
    static func fetchComments(postId: String) async throws -> [PostComment] {
        guard var components = URLComponents(string: FeedAPI.base + "/comments") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "postId", value: postId)
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        if let token = try? await AuthManager.shared.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "CommentService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PostComment].self, from: data)
    }

    static func postComment(
        postId: String,
        text: String,
        parentCommentId: String? = nil
    ) async throws -> PostComment {
        guard let url = URL(string: FeedAPI.base + "/comment") else {
            throw URLError(.badURL)
        }

        struct Payload: Encodable {
            let postId: String
            let text: String
            let parentCommentId: String?
        }

        var request = try await AuthManager.shared.authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Payload(postId: postId, text: text, parentCommentId: parentCommentId)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "CommentService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PostComment.self, from: data)
    }
}
