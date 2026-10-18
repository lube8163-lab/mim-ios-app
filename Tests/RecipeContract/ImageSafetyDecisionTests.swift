import XCTest
@testable import MimRecipeContract

final class ImageSafetyDecisionTests: XCTestCase {
    func testSafeMajorityPasses() {
        XCTAssertTrue(ImageSafetyDecision(nsfw: 0.01, nsfl: 0.01, sfw: 0.98).permitsDisplay)
    }
    func testSexualGoreAndUncertainResultsAreBlocked() {
        for result in [ImageSafetyDecision(nsfw: 0.8, nsfl: 0.01, sfw: 0.19),
                       .init(nsfw: 0.01, nsfl: 0.8, sfw: 0.19),
                       .init(nsfw: 0.25, nsfl: 0.25, sfw: 0.5)] {
            XCTAssertFalse(result.permitsDisplay)
        }
    }
    func testMissingInvalidAndUnnormalizedResultsFailClosed() {
        for result in [ImageSafetyDecision(nsfw: .nan, nsfl: 0, sfw: 1),
                       .init(nsfw: -0.1, nsfl: 0, sfw: 1.1),
                       .init(nsfw: 0, nsfl: 0, sfw: 0),
                       .init(nsfw: 0, nsfl: .infinity, sfw: 1)] {
            XCTAssertFalse(result.permitsDisplay)
        }
    }
    func testSafeCenterCannotOverrideBlockedEdgesOrMissingView() {
        let safe = ImageSafetyDecision(nsfw: 0.01, nsfl: 0.01, sfw: 0.98)
        let unsafe = ImageSafetyDecision(nsfw: 0.8, nsfl: 0.01, sfw: 0.19)
        for views in [[safe, unsafe], [unsafe, safe], [safe, .init(nsfw: .nan, nsfl: 0, sfw: 1)]] {
            XCTAssertEqual(ImageSafetyDecision.combining(views)?.permitsDisplay, false)
        }
        XCTAssertNil(ImageSafetyDecision.combining([]))
        XCTAssertEqual(ImageSafetyDecision.combining([safe, safe])?.permitsDisplay, true)
    }
}
