import XCTest
@testable import MimRecipeContract

final class CheckedMediaTests: XCTestCase {
    @MainActor func testRejectedOrUnavailableCheckerCannotSendOrReturnBytes() async throws {
        for expected in [ContentSafetyError.blocked, .unavailable] {
            var sent = false
            do {
                _ = try await CheckedMedia.send(Data([1, 2, 3]), check: { _ in throw expected }, send: { _ in sent = true })
                XCTFail("Expected a blocked operation")
            } catch { XCTAssertEqual(error as? ContentSafetyError, expected) }
            XCTAssertFalse(sent)
        }
    }

    @MainActor func testAllowedBytesAreSentOnlyAfterCheck() async throws {
        var events: [String] = []
        let data = Data([1, 2, 3])
        let result = try await CheckedMedia.send(data, check: { bytes in XCTAssertEqual(bytes, data); events.append("check") }, send: { bytes in
            events.append("send"); return bytes
        })
        XCTAssertEqual(events, ["check", "send"])
        XCTAssertEqual(result, data)
    }

    @MainActor func testCancellationBeforeSendDoesNotRunSender() async throws {
        var sent = false
        let task = Task { @MainActor in
            try await CheckedMedia.send(Data([1]), check: { _ in try Task.checkCancellation() }, send: { _ in sent = true })
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(sent)
    }
}
