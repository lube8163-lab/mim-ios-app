import Foundation
import CryptoKit

nonisolated struct PromptPolicy: Codable {
    let version: Int
    let blockedTerms: [String]
    var identity: String { get throws { try canonicalDigest(self) } }
    static func bundled() throws -> PromptPolicy {
        guard let url = Bundle.main.url(forResource: "prompt_safety_policy", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { throw RecipeError.invalid("投稿ポリシーを読み込めません。") }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    func validate(prompt: String) throws {
        // Keep the existing wire identity compatible with build39's published recipes.
        // Every rendering, including a legacy recipe, uses the current local content rules.
        try ContentSafetyPolicy.bundled().validate(prompt, context: .generationPrompt)
    }
}
