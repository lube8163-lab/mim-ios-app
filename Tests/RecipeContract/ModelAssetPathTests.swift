import XCTest
@testable import MimRecipeContract

final class ModelAssetPathTests: XCTestCase {
    func testSandboxAliasesProduceTheSameRelativePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("sd15")
        let file = root.appendingPathComponent("TextEncoder.mlmodelc/weights/weight.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        let alias = directory.appendingPathComponent("sandbox-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        for (candidate, base) in [(file, root), (file, alias), (alias.appendingPathComponent("TextEncoder.mlmodelc/weights/weight.bin"), root)] {
            XCTAssertEqual(try ModelAssetPath.relativePath(candidate, root: base), "TextEncoder.mlmodelc/weights/weight.bin")
        }
    }

    func testSiblingAndEscapingPathsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sd15")
        for path in [root, root.appendingPathComponent("../other/weight.bin"), root.deletingLastPathComponent().appendingPathComponent("sd15-extra/weight.bin")] {
            XCTAssertThrowsError(try ModelAssetPath.relativePath(path, root: root))
        }
    }
}
