import XCTest
@testable import MimRecipeContract

final class ModelDownloadPlanTests: XCTestCase {
    private func plan() throws -> ModelDownloadPlan {
        try .init(fragments: [3, 4, 2].enumerated().map { index, size in
            .init(url: URL(string: "https://example.com/part\(index)")!, bytes: Int64(size))
        })
    }
    func testResumeWithinFragmentKeepsEarlierFragments() throws {
        let remaining = try plan().remaining(at: 5)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].start, 3)
        XCTAssertEqual(remaining[0].offset, 2)
        XCTAssertEqual(remaining[1].start, 7)
        XCTAssertEqual(remaining[1].offset, 0)
    }
    func testBoundaryResumesAtNextFragmentAndCompletedDownloadHasNoRequests() throws {
        XCTAssertEqual(try plan().remaining(at: 3).first?.offset, 0)
        XCTAssertEqual(try plan().remaining(at: 3).first?.start, 3)
        XCTAssertTrue(try plan().remaining(at: 9).isEmpty)
        XCTAssertThrowsError(try plan().remaining(at: 10))
        XCTAssertThrowsError(try plan().remaining(at: -1))
    }
    func testInvalidLengthsAndOverflowAreRejected() {
        let url = URL(string: "https://example.com/part")!
        XCTAssertThrowsError(try ModelDownloadPlan(fragments: []))
        XCTAssertThrowsError(try ModelDownloadPlan(fragments: [.init(url: url, bytes: 0)]))
        XCTAssertThrowsError(try ModelDownloadPlan(fragments: [.init(url: url, bytes: Int64.max), .init(url: url, bytes: 1)]))
    }
}
