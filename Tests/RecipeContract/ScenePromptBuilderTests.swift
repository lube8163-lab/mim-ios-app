import XCTest
@testable import MimRecipeContract

final class ScenePromptBuilderTests: XCTestCase {
    private func build(_ prompt: String, subjects: [String], counts: String = "unknown", arrangement: String = "unknown", limit: Int) throws -> String {
        try ScenePromptBuilder.build(prompt: prompt, subjects: subjects, counts: counts, arrangement: arrangement,
            relationships: "unknown", colors: "unknown", background: "unknown", lighting: "unknown", medium: "unknown",
            maximumTokens: limit, tokenCount: { $0.split(separator: " ").count + 2 })
    }
    func testBothSubjectsSurviveLongDecorativeClause() throws {
        let result = try build("one red apple on the left, elaborate softly illuminated textured background with many details, one blue cup on the right",
            subjects: ["red apple", "blue cup"], limit: 16)
        XCTAssertTrue(result.contains("apple on the left"))
        XCTAssertTrue(result.contains("cup on the right"))
        XCTAssertFalse(result.contains("elaborate"))
    }
    func testCountsAndPlacementOutrankSecondaryDetails() throws {
        let result = try build("red apples, soft warm morning light on a rustic table", subjects: ["apples"],
            counts: "two apples", arrangement: "side by side", limit: 10)
        XCTAssertTrue(result.hasPrefix("two red apples, side by side"))
        XCTAssertFalse(result.contains("two apples,"))
    }
    func testEquivalentCountAndUnknownFieldsAreNotRepeated() throws {
        let result = try build("one apple on the left", subjects: ["apple"], counts: "apple: 1", arrangement: "left", limit: 77)
        XCTAssertEqual(result, "one apple on the left")
        XCTAssertFalse(result.contains("unknown"))
    }
    func testTooManyEssentialSubjectsFailsInsteadOfSilentlyTruncating() {
        XCTAssertThrowsError(try build("one apple on the left, one cup on the right", subjects: ["apple", "cup"], limit: 8))
    }
    func testSingleSubjectDoesNotBecomeTwoRequestsForTheSameObject() throws {
        let result = try build("A close-up of a red apple on a wooden surface", subjects: ["apple"], counts: "apple: single", arrangement: "apple: centered", limit: 77)
        XCTAssertEqual(result, "A close-up of one red apple on a wooden surface, centered")
    }
    func testGenericPromptGetsNamedSubjectsAndTheirPositions() throws {
        let result = try build("Two simple shapes, placed side by side on white", subjects: ["red circle", "blue square"],
            counts: "red circle: 1; blue square: 1", arrangement: "red circle: left; blue square: right", limit: 77)
        XCTAssertTrue(result.hasPrefix("one red circle on the left and one blue square on the right"))
        XCTAssertFalse(result.contains("Two simple shapes"))
    }
    func testPositionsStayAttachedToTheirNamedSubjects() throws {
        let result = try build("Two simple geometric shapes, one red circle and one blue square, placed side by side on white",
            subjects: ["red circle", "blue square"], counts: "red circle: 1; blue square: 1",
            arrangement: "red circle: left; blue square: right", limit: 77)
        XCTAssertEqual(result, "Two simple geometric shapes, one red circle on the left and one blue square on the right, placed side by side on white")
    }
}
