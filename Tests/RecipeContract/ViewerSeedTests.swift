import XCTest
@testable import MimRecipeContract

final class ViewerSeedTests: XCTestCase {
    private func recipe() -> GenerationRecipe {
        let model = ModelAssetManifest(schemaVersion: 1, modelID: "fixture", revision: "1", family: .sd15,
            width: 512, height: 512, files: [.init(path: "vocab.json", sha256: String(repeating: "a", count: 64), bytes: 1)])
        return .init(version: 2, prompt: "A red cup", negativePrompt: "", model: model,
            pipelineVersion: GenerationRecipe.pipelineVersion, promptFormatVersion: GenerationRecipe.promptFormatVersion,
            safetyPolicyIdentity: String(repeating: "b", count: 64), seed: nil, width: 512, height: 512,
            scheduler: "dpmSolverMultistep", steps: 25, guidance: 7.5, seedPolicy: .viewerRandom)
    }
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "mim.viewer-test.\(UUID().uuidString)")!
    }
    func testSharedRecipeOmitsSeedAndRejectsFixedSeedInV2() throws {
        let recipe = recipe()
        try recipe.validate()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe)) as? [String: Any])
        XCTAssertNil(object["seed"])
        XCTAssertEqual(object["seedPolicy"] as? String, "viewerRandom")
        object["seed"] = 42
        let invalid = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try invalid.validate())
    }
    func testClientsHaveIndependentSeedsAndReopeningKeepsLocalSeed() throws {
        let aDefaults = defaults()
        let a = ViewerSeedStore(defaults: aDefaults, randomSeed: { 123 })
        let b = ViewerSeedStore(defaults: defaults(), randomSeed: { 456 })
        let recipe = recipe()
        let aSeed = try a.seed(for: recipe, postID: "post-1")
        let bSeed = try b.seed(for: recipe, postID: "post-1")
        XCTAssertNotEqual(aSeed, bSeed)
        XCTAssertNotEqual(try recipe.renderCacheKey(seed: aSeed), try recipe.renderCacheKey(seed: bSeed))
        let reopened = ViewerSeedStore(defaults: aDefaults, randomSeed: { 999 })
        XCTAssertEqual(try reopened.seed(for: recipe, postID: "post-1"), aSeed)
    }
    func testExplicitRegenerationChangesSeedEvenOnRNGCollision() throws {
        let store = ViewerSeedStore(defaults: defaults(), randomSeed: { UInt32.max })
        let recipe = recipe()
        let first = try store.seed(for: recipe, postID: "post-1")
        let next = try store.seed(for: recipe, postID: "post-1", replacing: true)
        XCTAssertNotEqual(first, next)
        XCTAssertEqual(next, 0)
        XCTAssertEqual(try store.seed(for: recipe, postID: "post-1"), next)
        XCTAssertEqual(try store.seed(for: recipe, postID: "post-2"), UInt32.max)
    }
    func testPostingRemembersLocalPreviewWithoutSharingItsSeed() throws {
        let store = ViewerSeedStore(defaults: defaults(), randomSeed: { 999 })
        let recipe = recipe()
        try store.remember(42, for: recipe, postID: "server-id")
        XCTAssertEqual(try store.seed(for: recipe, postID: "server-id"), 42)
        XCTAssertNil(recipe.seed)
    }
    func testLegacyRecipesStillUseTheirPublishedSeed() throws {
        let v2 = recipe()
        let legacy = GenerationRecipe(version: 1, prompt: v2.prompt, negativePrompt: "", model: v2.model,
            pipelineVersion: v2.pipelineVersion, promptFormatVersion: v2.promptFormatVersion,
            safetyPolicyIdentity: v2.safetyPolicyIdentity, seed: 42, width: 512, height: 512,
            scheduler: v2.scheduler, steps: v2.steps, guidance: v2.guidance)
        let store = ViewerSeedStore(defaults: defaults(), randomSeed: { 999 })
        XCTAssertEqual(try store.seed(for: legacy, postID: "old-post", replacing: true), 42)
        XCTAssertEqual(try legacy.renderCacheKey(seed: 42), try legacy.cacheKey)
    }
    func testV2RequiresExplicitServerCapability() {
        XCTAssertFalse(RecipeServerCapabilities(promptOnlyRecipeVersions: [1]).supports(2))
        XCTAssertTrue(RecipeServerCapabilities(promptOnlyRecipeVersions: [1, 2]).supports(2))
    }
}
