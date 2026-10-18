import XCTest
@testable import MimRecipeContract

final class DiffusionModelShapeTests: XCTestCase {
    func testDistributedSD15ModelWithUndeclaredDecoderOutput() throws {
        // Descriptors from the checksum-verified sd15_coreml_v2 archive.
        XCTAssertEqual(try DiffusionModelShapes.imageWidth(unet: [2, 4, 64, 64],
            decoderInput: [1, 4, 64, 64], decoderOutput: []), 512)
    }
    func testDeclaredOutputMustAgreeWithBothLatentInputs() throws {
        XCTAssertEqual(try DiffusionModelShapes.imageWidth(unet: [2, 4, 128, 128],
            decoderInput: [1, 4, 128, 128], decoderOutput: [1, 3, 1024, 1024]), 1024)
        XCTAssertThrowsError(try DiffusionModelShapes.imageWidth(unet: [2, 4, 64, 64],
            decoderInput: [1, 4, 64, 64], decoderOutput: [1, 3, 1024, 1024]))
        XCTAssertThrowsError(try DiffusionModelShapes.imageWidth(unet: [2, 4, 64, 64],
            decoderInput: [1, 4, 64, 64], decoderOutput: [1, 4, 512, 512]))
    }
    func testAbsentOutputShapeStillRejectsMismatchedInputs() {
        XCTAssertThrowsError(try DiffusionModelShapes.imageWidth(unet: [2, 4, 64, 64],
            decoderInput: [1, 4, 128, 128], decoderOutput: []))
        XCTAssertThrowsError(try DiffusionModelShapes.imageWidth(unet: [2, 4, 64, 64],
            decoderInput: [1, 3, 64, 64], decoderOutput: []))
    }
    func testUnsupportedOrNonSquareLatentIsRejected() {
        for shape in [[2, 4, 64, 96], [2, 4, 32, 32], [4, 64, 64]] {
            XCTAssertThrowsError(try DiffusionModelShapes.imageWidth(unet: shape,
                decoderInput: [1, 4, 64, 64], decoderOutput: []))
        }
    }
}
