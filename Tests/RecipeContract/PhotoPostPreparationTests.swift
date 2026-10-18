import XCTest
@testable import MimRecipeContract

final class PhotoPostPreparationTests: XCTestCase {
    private func job() -> PhotoPostPreparation {
        .init(id: "3eedca40-6a88-4014-a260-82163adbbfa0", ownerID: "fixture", displayName: "Fixture",
              avatarURL: "", userText: "hello", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
    func testPersistedUnconfirmedPostRetriesWithTheSameIDAndNoPhotoPayload() throws {
        var value = job(); value.stage = .failed; value.message = "lost receipt"
        var restored = try JSONDecoder().decode(PhotoPostPreparation.self, from: canonicalData(value))
        restored.retry()
        XCTAssertEqual(restored.stage, .queued)
        XCTAssertEqual(restored.id, value.id)
        XCTAssertNil(restored.message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: canonicalData(restored.pendingPayload)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["mode", "hasImage", "photoProcessing", "tags", "clientPostID", "userText"])
        XCTAssertEqual(json["clientPostID"] as? String, value.id)
        XCTAssertEqual(json["photoProcessing"] as? String, "pending")
    }
    func testAcceptedJobSurvivesRelaunchWithoutBecomingANewPost() throws {
        var value = job(); value.stage = .failed; value.accepted = true
        var restored = try JSONDecoder().decode(PhotoPostPreparation.self, from: canonicalData(value))
        restored.retry()
        XCTAssertEqual(restored.stage, .accepted)
        XCTAssertTrue(restored.accepted)
        XCTAssertEqual(restored.id, value.id)
    }
}
