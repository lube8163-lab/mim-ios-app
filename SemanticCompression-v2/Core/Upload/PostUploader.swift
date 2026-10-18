import Foundation

struct PostUploadResponse: Decodable {
    let ok: Bool
    let id: String
    let createdAt: Date
    let recipeDigest: String?
}

enum PostUploadError: Error, LocalizedError {
    case preflight(String)
    case unconfirmed(String)
    var postMayHaveBeenSaved: Bool { if case .unconfirmed = self { return true }; return false }
    var errorDescription: String? {
        switch self {
        case .preflight(let message): return message
        case .unconfirmed:
            return "投稿の保存を確認できませんでした。二重投稿を避けるため、再送せず投稿一覧を確認してください。"
        }
    }
}

@MainActor
final class PostUploader {
    func upload(post: Post) async throws -> PostUploadResponse {
        let request: URLRequest
        do { request = try await prepareRequest(post: post) }
        catch { throw PostUploadError.preflight(error.localizedDescription) }
        do { return try await send(request, post: post) }
        catch { throw PostUploadError.unconfirmed(error.localizedDescription) }
    }

    private func prepareRequest(post: Post) async throws -> URLRequest {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mim-ui-review") {
            throw RecipeError.unsupported("レビュー用起動では投稿を送信しません。")
        }
        #endif
        try Task.checkCancellation()
        let contentPolicy = try ContentSafetyPolicy.bundled()
        try contentPolicy.validate(post.userText)
        try contentPolicy.validate(post.caption)
        try contentPolicy.validate(post.tags.joined(separator: " "))
        try contentPolicy.validate(post.recipe?.prompt, context: .generationPrompt)
        if post.hasImage {
            guard let recipe = post.recipe else { throw RecipeError.invalid("再現プレビューを作成してください。") }
            try recipe.validate()
            // Old servers may silently drop unknown fields. Require an explicit capability first.
            let (data, response) = try await URLSession.shared.data(from: URL(string: FeedAPI.base + "/capabilities")!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let capabilities = try? JSONDecoder().decode(RecipeServerCapabilities.self, from: data),
                  capabilities.supports(recipe.version) else {
                throw RecipeError.unsupported("写真の投稿はサーバーの更新が必要です。プレビューは端末内で確認できます。")
            }
        }
        let body = PostUploadPayload(caption: post.caption, semanticPrompt: post.recipe?.prompt,
                                     tags: post.tags, imageUnderstandingBackend: post.hasImage ? post.imageUnderstandingBackend : nil,
                                     userText: post.userText, hasImage: post.hasImage, recipe: post.recipe)
        var request = try await AuthManager.shared.authorizedRequest(url: URL(string: FeedAPI.base + "/post")!, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("mim-prompt-only-v1", forHTTPHeaderField: "X-Mim-Post-Format")
        request.httpBody = try canonicalData(body)
        try Task.checkCancellation()
        return request
    }

    private func send(_ request: URLRequest, post: Post) async throws -> PostUploadResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(PostUploadResponse.self, from: data)
        guard result.ok else { throw URLError(.badServerResponse) }
        if let recipe = post.recipe {
            guard result.recipeDigest == (try canonicalDigest(recipe)) else {
                throw RecipeError.unsupported("投稿先で再現設定の保存を確認できませんでした。再送せず投稿一覧を確認してください。")
            }
        }
        return result
    }
}
