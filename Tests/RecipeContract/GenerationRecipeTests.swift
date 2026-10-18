import XCTest
@testable import MimRecipeContract

final class GenerationRecipeTests: XCTestCase {
    func testCanonicalDigestMatchesJavaScriptContract() throws {
        XCTAssertEqual(try canonicalDigest(recipe()), "18c0ea266f751c8ffe0aa67336bafb9e0d4d5aadded6b0debc49f6c532c1d040")
    }
    func manifest(revision: String = "test-v1", width: Int = 512, family: PipelineFamily = .sd15) -> ModelAssetManifest {
        .init(schemaVersion: 1, modelID: "fixture", revision: revision, family: family, width: width, height: width,
              files: [.init(path: "vocab.json", sha256: String(repeating: "a", count: 64), bytes: 10)])
    }
    func recipe(seed: UInt32 = 42, prompt: String = "One red cup on a white table", model: ModelAssetManifest? = nil) -> GenerationRecipe {
        let model = model ?? manifest()
        return .init(version: 1, prompt: prompt, negativePrompt: "", model: model,
                     pipelineVersion: GenerationRecipe.pipelineVersion, promptFormatVersion: GenerationRecipe.promptFormatVersion,
                     safetyPolicyIdentity: String(repeating: "b", count: 64), seed: seed, width: model.width, height: model.height,
                     scheduler: "dpmSolverMultistep", steps: 25, guidance: 7.5)
    }
    func testRoundTripKeepsPreviewAndReceivedIdentity() throws {
        let beforePosting = recipe()
        let received = try JSONDecoder().decode(GenerationRecipe.self, from: canonicalData(beforePosting))
        XCTAssertEqual(received, beforePosting)
        XCTAssertEqual(try received.cacheKey, try beforePosting.cacheKey)
        try received.validate(installedManifest: manifest())
    }
    func testEveryRenderingSettingChangesCacheIdentity() throws {
        let base = try recipe().cacheKey
        XCTAssertNotEqual(base, try recipe(seed: 43).cacheKey)
        XCTAssertNotEqual(base, try recipe(prompt: "Two red cups on a white table").cacheKey)
        XCTAssertNotEqual(base, try recipe(model: manifest(revision: "test-v2")).cacheKey)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe())) as? [String: Any])
        for (key, value) in [("steps", 30), ("guidance", 8)] {
            object[key] = value
            let changed = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNotEqual(base, try changed.cacheKey)
        }
    }
    func testAssetMismatchIsRejected() throws {
        XCTAssertThrowsError(try recipe().validate(installedManifest: manifest(revision: "other"))) {
            XCTAssertEqual($0 as? RecipeError, .modelMismatch)
        }
    }
    func testKnownLegacySD15PathOffsetKeepsRecipeDigestAndAcceptsIdenticalAssets() throws {
        let current = sd15Manifest(path: "TextEncoder.mlmodelc/weights/weight.bin")
        let legacy = sd15Manifest(path: "on/sd15/TextEncoder.mlmodelc/weights/weight.bin")
        let oldRecipe = recipe(model: legacy)
        let originalDigest = try oldRecipe.cacheKey
        try oldRecipe.validate(installedManifest: current)
        try recipe(model: current).validate(installedManifest: legacy)
        XCTAssertEqual(try oldRecipe.cacheKey, originalDigest)
        XCTAssertNotEqual(try legacy.identity, try current.identity)
        XCTAssertEqual(try legacy.normalizedForComparison.identity, try current.identity)
    }
    func testLegacyPathCompatibilityStillRejectsChangedWeightsAndUnknownPrefixes() throws {
        let current = sd15Manifest(path: "TextEncoder.mlmodelc/weights/weight.bin")
        for other in [sd15Manifest(path: "on/sd15/TextEncoder.mlmodelc/weights/weight.bin", hash: "c"),
                      sd15Manifest(path: "other/sd15/TextEncoder.mlmodelc/weights/weight.bin"),
                      sd15Manifest(path: "on/sd15/TextEncoder.mlmodelc/weights/weight.bin", revision: "other") ] {
            XCTAssertThrowsError(try recipe(model: other).validate(installedManifest: current)) {
                XCTAssertEqual($0 as? RecipeError, .modelMismatch)
            }
        }
        XCTAssertThrowsError(try recipe(model: sd15Manifest(path: "on/sd15/")).validate(installedManifest: current))
    }
    private func sd15Manifest(path: String, hash: Character = "a", revision: String = "coreml-v2") -> ModelAssetManifest {
        .init(schemaVersion: 1, modelID: "sd15", revision: revision, family: .sd15, width: 512, height: 512,
              files: [.init(path: path, sha256: String(repeating: String(hash), count: 64), bytes: 10)])
    }
    func testImageDTOHasOnlyAllowlistedTextAndRecipeFields() throws {
        let dto = PostUploadPayload(caption: "A cup", semanticPrompt: recipe().prompt, tags: ["cup"],
                                    imageUnderstandingBackend: "foundationModels", userText: "hello", hasImage: true, recipe: recipe())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(dto)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["mode", "caption", "semanticPrompt", "tags", "imageUnderstandingBackend", "userText", "hasImage", "recipe"]))
        XCTAssertEqual(object["mode"] as? Int, 1)
        let serialized = String(decoding: try canonicalData(dto), as: UTF8.self).lowercased()
        for banned in ["thumbhash", "coeffs_b64", "pixels_b64", "jpegbase64", "lowresguide", "latent", "embedding"] {
            XCTAssertFalse(serialized.contains(banned))
        }
    }
    func testUnknownRecipeVersionAndPlaceholderAreRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe())) as? [String: Any])
        object["version"] = 2
        let unknown = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try unknown.validate())
        XCTAssertThrowsError(try recipe(prompt: "simple scene").validate())
    }
    func testLegacyLCMScheduleIsNotAMimRecipe() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe())) as? [String: Any])
        for scheduler in ["lcm", "lcmScheduler", "LCMScheduler"] {
            object["scheduler"] = scheduler
            object["steps"] = 4
            let legacy = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try legacy.validate())
        }
    }
    func testSDXL768And1024SupportedSanaIs512Only() throws {
        try recipe(model: manifest(width: 768, family: .sdxl)).validate()
        try recipe(model: manifest(width: 1024, family: .sdxl)).validate()
        XCTAssertThrowsError(try manifest(width: 768, family: .sanaSprint06B).validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe(model: manifest(family: .sanaSprint06B)))) as? [String: Any])
        object["scheduler"] = "scm-trigflow"; object["steps"] = 2; object["negativePrompt"] = "ignore this"
        let unsupported = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try unsupported.validate())
    }
    func testAvailabilityNeverTurnsAnUnavailableModelIntoSuccess() {
        for state in [PhotoUnderstandingAvailability.unsupportedDevice, .intelligenceDisabled, .preparing, .unavailable] {
            XCTAssertFalse(state.canAnalyze)
            XCTAssertFalse(state.message.isEmpty)
        }
        XCTAssertTrue(PhotoUnderstandingAvailability.available.canAnalyze)
    }
    func testUnknownAPICapabilityDoesNotEnableUpload() throws {
        XCTAssertFalse(RecipeServerCapabilities(promptOnlyRecipeVersions: []).supportsV1)
        XCTAssertFalse(RecipeServerCapabilities(promptOnlyRecipeVersions: [2]).supportsV1)
        XCTAssertThrowsError(try JSONDecoder().decode(RecipeServerCapabilities.self, from: Data("{}".utf8)))
    }
    func testTraversalAndDuplicateManifestEntriesAreRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(manifest())) as? [String: Any])
        object["files"] = [["path": "../vocab.json", "sha256": String(repeating: "a", count: 64), "bytes": 10]]
        let bad = try JSONDecoder().decode(ModelAssetManifest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try bad.validate())
        object["files"] = [manifest().files[0], manifest().files[0]].map {
            ["path": $0.path, "sha256": $0.sha256, "bytes": $0.bytes] as [String: Any]
        }
        let duplicate = try JSONDecoder().decode(ModelAssetManifest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try duplicate.validate())
    }
    func testPostRoutesValidateURLAndNotificationIdentifiers() {
        XCTAssertEqual(PostDestination.postID(from: URL(string: "mim://post/abc-123")!), "abc-123")
        XCTAssertEqual(PostDestination.postID(from: ["data": ["postId": "abc-123"]]), "abc-123")
        for value in ["mim://post/../x", "mim://post/a/b", "https://post/a", "mim://post/a?image=secret"] {
            XCTAssertNil(PostDestination.postID(from: URL(string: value)!))
        }
        XCTAssertNil(PostDestination.postID(from: ["postId": "../../secret"]))
        XCTAssertEqual(PostDestination.followUserID(from: ["type": "follow", "actorUserId": "mim-guide-bot"]), "mim-guide-bot")
        XCTAssertNil(PostDestination.followUserID(from: ["type": "like", "actorUserId": "mim-guide-bot"]))
        XCTAssertNil(PostDestination.followUserID(from: ["type": "follow", "actorUserId": "../../secret"]))
        XCTAssertNil(PostDestination.followUserID(from: ["type": "follow"]))
    }
    func testInvalidSafetyDigestIsRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(recipe())) as? [String: Any])
        object["safetyPolicyIdentity"] = String(repeating: "z", count: 64)
        let invalid = try JSONDecoder().decode(GenerationRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try invalid.validate())
    }
}
