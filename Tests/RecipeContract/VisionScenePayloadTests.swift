import XCTest
@testable import MimRecipeContract

final class VisionScenePayloadTests: XCTestCase {
    func testObservedNestedSubjectsPreserveCountAndPositionsWithoutDuplicatingPrompt() throws {
        let result = try VisionScenePayload.parse(#"{"subjects":[{"name":"apple","count":2,"arrangement":"side by side","colors":["red"]}],"description":"Two red apples on a wooden surface","generationPrompt":"two red apples on a wooden surface"}"#)
        XCTAssertEqual(result.subjects, ["apple"])
        XCTAssertEqual(result.counts, "apple: 2")
        XCTAssertEqual(result.arrangement, "apple: side by side")
        XCTAssertEqual(result.generationPrompt, "two red apples on a wooden surface")
        XCTAssertEqual(result.background, "unknown")
    }
    func testFencedJSONAndStringSubjectsAreSupported() throws {
        let result = try VisionScenePayload.parse("```json\n" + #"{"subjects":["red circle","blue square"],"description":"A graphic","generationPrompt":"A red circle on the left and a blue square on the right"}"# + "\n```")
        XCTAssertEqual(result.subjects.count, 2)
        XCTAssertEqual(result.counts, "unknown")
    }
    func testMalformedAndIncompleteOutputsTriggerFallback() {
        for response in ["<image>", "{}", #"{"subjects":[],"description":"x","generationPrompt":"x"}"#,
            #"{"subjects":["x"],"description":"x","generationPrompt":"x"} trailing text"#,
            #"{"subjects":["unknown"],"description":"unknown","generationPrompt":"unknown"}"#] {
            XCTAssertThrowsError(try VisionScenePayload.parse(response))
        }
    }
    func testBooleanAndFractionalCountsAreNotTurnedIntoInventedCounts() throws {
        for value in ["true", "2.5"] {
            let result = try VisionScenePayload.parse("{\"subjects\":[{\"name\":\"apple\",\"count\":\(value)}],\"description\":\"A fruit\",\"generationPrompt\":\"A fruit\"}")
            XCTAssertEqual(result.counts, "unknown")
        }
    }
}
