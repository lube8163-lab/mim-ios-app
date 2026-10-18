import XCTest
@testable import MimRecipeContract

final class UnderstandingFallbackTests: XCTestCase {
    private let ready = ProviderAvailability(status: .ready, message: "ready")

    @MainActor func testReadyPrimaryIsUsedWithoutCallingFallback() async throws {
        var fallbackCalled = false
        let output = try await UnderstandingFallback.run(primaryAvailability: ready, fallbackAvailability: ready,
            primary: { "CoreAI" }, fallback: { fallbackCalled = true; return "AFM" })
        XCTAssertEqual(output.result, "CoreAI")
        XCTAssertNil(output.reason)
        XCTAssertFalse(fallbackCalled)
    }
    @MainActor func testMissingPrimaryAssetsUseFallbackAndRecordReason() async throws {
        var primaryCalled = false
        let output = try await UnderstandingFallback.run(primaryAvailability: .coreAI(sdkAvailable: true),
            fallbackAvailability: ready, primary: { primaryCalled = true; return "CoreAI" }, fallback: { "AFM" })
        XCTAssertFalse(primaryCalled)
        XCTAssertEqual(output.result, "AFM")
        XCTAssertNotNil(output.reason)
    }
    @MainActor func testPrimaryInferenceFailureUsesFallback() async throws {
        let output = try await UnderstandingFallback.run(primaryAvailability: ready, fallbackAvailability: ready,
            primary: { () async throws -> String in throw RecipeError.invalid("Inference failed") }, fallback: { "AFM" })
        XCTAssertEqual(output.result, "AFM")
        XCTAssertEqual(output.reason, "Inference failed")
    }
    @MainActor func testCancellationNeverStartsFallback() async {
        var fallbackCalled = false
        do {
            _ = try await UnderstandingFallback.run(primaryAvailability: ready, fallbackAvailability: ready,
                primary: { () async throws -> String in throw CancellationError() }, fallback: { fallbackCalled = true; return "AFM" })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(fallbackCalled)
    }
    @MainActor func testBothUnavailableCannotBecomeAPlaceholderSuccess() async {
        let unavailable = ProviderAvailability(status: .unavailable, message: "Unavailable")
        var fallbackCalled = false
        do {
            _ = try await UnderstandingFallback.run(primaryAvailability: unavailable, fallbackAvailability: unavailable,
                primary: { "CoreAI" }, fallback: { fallbackCalled = true; return "simple scene" })
            XCTFail("Expected unavailable error")
        } catch { XCTAssertFalse(fallbackCalled) }
    }
}
