import Foundation

// Local rendering state is never part of the shared post or an uploaded recipe.
nonisolated final class ViewerSeedStore: @unchecked Sendable {
    static let shared = ViewerSeedStore(defaults: .standard)
    private let defaults: UserDefaults
    private let randomSeed: @Sendable () -> UInt32
    private let lock = NSLock()

    init(defaults: UserDefaults, randomSeed: @escaping @Sendable () -> UInt32 = { UInt32.random(in: .min ... .max) }) {
        self.defaults = defaults
        self.randomSeed = randomSeed
    }

    func seed(for recipe: GenerationRecipe, postID: String, replacing: Bool = false) throws -> UInt32 {
        try recipe.validate()
        if let legacySeed = recipe.seed { return legacySeed }
        let key = try storageKey(recipe, postID: postID)
        lock.lock(); defer { lock.unlock() }
        let previous = (defaults.object(forKey: key) as? NSNumber)?.uint32Value
        if let previous, !replacing { return previous }
        var value = randomSeed()
        if value == previous { value &+= 1 }
        defaults.set(NSNumber(value: value), forKey: key)
        return value
    }

    func remember(_ seed: UInt32, for recipe: GenerationRecipe, postID: String) throws {
        try recipe.validate()
        guard recipe.version == 2 else { return }
        let key = try storageKey(recipe, postID: postID)
        lock.lock(); defer { lock.unlock() }
        defaults.set(NSNumber(value: seed), forKey: key)
    }

    private func storageKey(_ recipe: GenerationRecipe, postID: String) throws -> String {
        guard !postID.isEmpty else { throw RecipeError.invalid("投稿の識別情報がありません。") }
        return "mim.viewer-seed.v1." + (try canonicalDigest(Identity(postID: postID, recipe: recipe)))
    }
    private struct Identity: Encodable { let postID: String; let recipe: GenerationRecipe }
}
