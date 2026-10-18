import XCTest
@testable import MimRecipeContract

final class ContentSafetyPolicyTests: XCTestCase {
    func testBenignMultilingualHealthAndOrdinaryTextPass() throws {
        let policy = try ContentSafetyPolicy.bundled()
        for text in ["A quiet study room", "sexual health and sex education", "pornography addiction support",
                     "stars visible to the naked eye", "naked mole rat", "性教育について学ぶ", "医学と健康の話",
                     "educación sexual y salud sexual", "educação sexual e saúde sexual", "성교육 자료", "性健康教育", "一杯咖啡"] {
            XCTAssertNoThrow(try policy.validate(text), text)
        }
        XCTAssertNoThrow(try policy.validate("A sexual health education poster", context: .generationPrompt))
        XCTAssertNoThrow(try policy.validate("Immigrants are not subhuman"))
        XCTAssertNoThrow(try policy.validate("A 12-year-old portrait", context: .generationPrompt))
        XCTAssertNoThrow(try policy.validate("18歳の性的な健康相談"))
        XCTAssertNoThrow(try policy.validate("28歳の性的な健康相談"))
    }

    func testExplicitPatternsAcrossLanguagesAndObfuscationAreBlocked() throws {
        let policy = try ContentSafetyPolicy.bundled()
        for text in ["porn", "ＰＯＲＮ", "p\u{200b}orn", "pоrn", "p.o.r.n", "ポルノ", "色情视频", "色情影片", "포르노", "porno"] {
            XCTAssertThrowsError(try policy.validate(text), text)
        }
        XCTAssertThrowsError(try policy.validate("I will kill you"))
        XCTAssertThrowsError(try policy.validate("お前を殺してやる"))
        XCTAssertThrowsError(try policy.validate("未成年の性的な写真"))
        XCTAssertThrowsError(try policy.validate("12-year-old sexual photo"))
        XCTAssertThrowsError(try policy.validate("12歳の性的な写真"))
        XCTAssertThrowsError(try policy.validate("sexual health and porn")) // no whole-message exemption
    }

    func testWholeWordsAndContextAvoidSubstringAndDistantMatches() throws {
        let policy = try ContentSafetyPolicy.bundled()
        XCTAssertNoThrow(try policy.validate("Sussex is a county. A popcorn snack."))
        XCTAssertNoThrow(try policy.validate("A child studies. " + String(repeating: "quiet ", count: 40) + "A book about sexual health."))
        XCTAssertThrowsError(try policy.validate("A naked person", context: .generationPrompt))
        XCTAssertNoThrow(try policy.validate("A quiet bedroom", context: .generationPrompt))
    }

    func testPolicyMissingMalformedAndOversizeAreFailClosed() throws {
        XCTAssertThrowsError(try ContentSafetyPolicy.decode(Data("{}".utf8)))
        let policy = try ContentSafetyPolicy.bundled()
        XCTAssertThrowsError(try policy.validate(String(repeating: "x", count: 4001)))
        XCTAssertThrowsError(try policy.validate(String(repeating: "😀", count: 2001)))
        XCTAssertNoThrow(try policy.validate(nil))
    }

    func testOldRecipeWireIdentityIsPreservedButCurrentRulesAreApplied() throws {
        let old = PromptPolicy(version: 2, blockedTerms: ["nude", "sex"])
        XCTAssertNoThrow(try old.validate(prompt: "sexual health education poster"))
        XCTAssertThrowsError(try old.validate(prompt: "色情图片"))
    }

    func testRecipeValidationBeforeCacheLookupRejectsCurrentBlockedPrompt() throws {
        let manifest = ModelAssetManifest(schemaVersion: 1, modelID: "sd15", revision: "test", family: .sd15,
            width: 512, height: 512, files: [.init(path: "dummy", sha256: String(repeating: "a", count: 64), bytes: 1)])
        let recipe = GenerationRecipe.photo(prompt: "色情图片", manifest: manifest, safetyPolicyIdentity: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try recipe.validate())
    }
}
