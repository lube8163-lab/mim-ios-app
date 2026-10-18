import Foundation
import CryptoKit

nonisolated enum CoreAIVisionAssets {
    static let modelID = "LiquidAI/LFM2.5-VL-450M"
    static let revision = "f6648f9c65402a4d5c280cae41b672f977e74e3a"
    static let installPath = "CoreAI/lfm2-vl-450m-f6648f9-v1"
    static let archiveSHA256 = "1f98ffb670b4e3a22964f07c5542a3841677d0d8bcd5158276ab34d9095ec33d"
    static let manifestSHA256 = "db43e75117e757234c97b6cb1d262c25cbf1dd4ebaa7b6758e7495326ff121a6"
    static let decoderPath = "gpu-pipelined/lfm2_5_vl_450m_decode_int8lin"
    static let visionPath = "gpu-pipelined/lfm2_5_vl_450m_vision_fp16"
    static let fragments: [ModelDownloadFragment] = {
        let base = "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/CoreAI/vlm/lfm2-vl-450m-f6648f9-v1/lfm2_5_vl_450m_coreai_f6648f9_v1.zip.part"
        return [200_000_000, 200_000_000, 154_278_020].enumerated().map { index, bytes in
            .init(url: URL(string: base + String(format: "%03d", index + 1))!, bytes: Int64(bytes))
        }
    }()

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let kind: String
        let modelID: String
        let revision: String
        let decoderPath: String
        let visionPath: String
        let files: [ModelAssetFile]
    }

    static func installed(at root: URL) -> Bool { (try? validate(at: root, verifyHashes: false)) != nil }

    static func validate(at root: URL, verifyHashes: Bool) throws {
        let fm = FileManager.default
        let data = try Data(contentsOf: root.appendingPathComponent("coreai-assets.json"))
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == manifestSHA256 else {
            throw RecipeError.modelMismatch
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.kind == "CoreAIVisionAssetPackage",
              manifest.modelID == modelID, manifest.revision == revision,
              manifest.decoderPath == decoderPath, manifest.visionPath == visionPath,
              manifest.files.count == 11, Set(manifest.files.map(\.path)).count == manifest.files.count else {
            throw RecipeError.modelMismatch
        }
        for file in manifest.files {
            try Task.checkCancellation()
            guard file.bytes > 0, !file.path.hasPrefix("/"), !file.path.contains("\\"),
                  !file.path.split(separator: "/").contains("..") else { throw RecipeError.modelMismatch }
            let url = root.appendingPathComponent(file.path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == Int(file.bytes) else { throw RecipeError.modelMismatch }
            if verifyHashes {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var hash = SHA256()
                while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty {
                    try Task.checkCancellation(); hash.update(data: block)
                }
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                    throw RecipeError.modelMismatch
                }
            }
        }
        guard fm.fileExists(atPath: root.appendingPathComponent("LICENSE.txt").path) else { throw RecipeError.modelMismatch }
    }
}
