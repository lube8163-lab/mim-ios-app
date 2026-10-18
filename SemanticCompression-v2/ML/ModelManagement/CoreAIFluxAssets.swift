import Foundation
import CryptoKit

nonisolated enum CoreAIFluxAssets {
    static let modelID = "flux2-klein-4b"
    static let revision = "coreai-512-4bit-a7f65cd-v1"
    static let installPath = "CoreAI/flux2-klein-4b-512-a7f65cd-v1"
    static let archiveSHA256 = "9eee2a1226677c396c165b7204d912a3c1d785fd89aa8b7b22b7aa7ac3af3968"
    static let archiveBytes: Int64 = 3542141404
    static let installedBytes: Int64 = 4_043_710_174
    static let fragments: [ModelDownloadFragment] = [
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part001")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part002")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part003")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part004")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part005")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part006")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part007")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part008")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part009")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part010")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part011")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part012")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part013")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part014")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part015")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part016")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part017")!, bytes: 200000000),
        .init(url: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/generation/flux2-klein-4b-512-a7f65cd-v1/flux2_klein_4b_512_coreai_a7f65cd_v1.zip.part018")!, bytes: 142141404)
    ]

    static var runtimeSupported: Bool {
        #if canImport(CoreAI) && !targetEnvironment(simulator)
        if #available(iOS 27.0.1, *) { return ProcessInfo.processInfo.physicalMemory >= 7_500_000_000 }
        #endif
        return false
    }
    static func catalog() throws -> ModelAssetManifest {
        guard let url = Bundle.main.url(forResource: "flux2-catalog-manifest", withExtension: "json") else {
            throw RecipeError.modelMismatch
        }
        let manifest = try JSONDecoder().decode(ModelAssetManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        guard manifest.modelID == modelID, manifest.revision == revision, manifest.family == .flux2Klein4B,
              manifest.width == 512, manifest.files.count == 17 else { throw RecipeError.modelMismatch }
        return manifest
    }
    static func installed(at root: URL) -> Bool { (try? validate(at: root, verifyHashes: false)) != nil }
    static func validate(at root: URL, verifyHashes: Bool) throws {
        let manifest = try catalog()
        for file in manifest.files {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(file.path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Int(file.bytes) else { throw RecipeError.modelMismatch }
            if verifyHashes {
                guard try ModelAssets.fileSHA256(at: url) == file.sha256 else {
                    throw RecipeError.modelMismatch
                }
            }
        }
    }
}
