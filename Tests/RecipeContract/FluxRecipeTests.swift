import XCTest
@testable import MimRecipeContract

final class FluxRecipeTests: XCTestCase {
    func testFluxDigestMatchesJavaScriptAndServerRecipe() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let recipe = try JSONDecoder().decode(GenerationRecipe.self,
            from: Data(contentsOf: root.appendingPathComponent("server/flux-recipe-fixture.json")))
        try recipe.validate()
        XCTAssertEqual(try canonicalDigest(recipe), "adc06a7f6ad4a75dc49c593b8788f4cf42862f984a448607e24867bc1fd3a1ac")
    }
    func manifest() -> ModelAssetManifest {
        .init(schemaVersion: 1, modelID: "flux2-klein-4b", revision: "coreai-512-4bit-a7f65cd-v1",
              family: .flux2Klein4B, width: 512, height: 512,
              files: [.init(path: "Transformer_512.aimodel/main.mlirb", sha256: String(repeating: "a", count: 64), bytes: 100)])
    }
    func testPhotoUsesDistilledFluxSettingsAndClientSeeds() throws {
        let recipe = GenerationRecipe.photo(prompt: "One cup on a table", manifest: manifest(), safetyPolicyIdentity: String(repeating: "b", count: 64))
        try recipe.validate(installedManifest: manifest())
        XCTAssertEqual(recipe.pipelineVersion, "mim-coreai-flux2-t2i-v1")
        XCTAssertEqual(recipe.promptFormatVersion, "scene-en-flux2-v1")
        XCTAssertEqual(recipe.scheduler, "discreteFlow")
        XCTAssertEqual(recipe.steps, 4); XCTAssertEqual(recipe.guidance, 1)
        XCTAssertEqual(recipe.negativePrompt, ""); XCTAssertNil(recipe.seed)
        XCTAssertEqual(recipe.seedPolicy, .viewerRandom)
        XCTAssertNotEqual(try recipe.renderCacheKey(seed: 42), try recipe.renderCacheKey(seed: 43))
    }
    func testIncorrectFluxSettingsAreRejected() throws {
        let recipe = GenerationRecipe.photo(prompt: "One cup", manifest: manifest(), safetyPolicyIdentity: String(repeating: "b", count: 64))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe)) as? [String: Any])
        for (field, value) in [("steps", 2 as Any), ("guidance", 7.5 as Any), ("scheduler", "dpmSolverMultistep" as Any),
                               ("negativePrompt", "bad anatomy" as Any), ("pipelineVersion", GenerationRecipe.pipelineVersion as Any)] {
            var object = original; object[field] = value
            let altered = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try altered.validate(), field)
        }
    }
    func testFluxPromptKeepsSupportRelationsAndPlacement() throws {
        let prompt = try ScenePromptBuilder.flux(prompt: "An orange chair and a cup", counts: "cup: 1",
            arrangement: "chair: left; cup: center", relationships: "cup on the table", colors: "orange, white",
            background: "unknown", lighting: "daylight", medium: "photo")
        XCTAssertTrue(prompt.contains("chair: left")); XCTAssertTrue(prompt.contains("cup on the table"))
        XCTAssertFalse(prompt.contains("unknown"))
    }
}
