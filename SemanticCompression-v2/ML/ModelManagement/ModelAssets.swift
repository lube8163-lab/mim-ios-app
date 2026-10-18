import Foundation
import CryptoKit
import CoreML

nonisolated enum ModelAssets {
    private struct FileState: Codable {
        let path: String
        let bytes: Int
        let modified: Double
    }
    static func inventoryFingerprint(at root: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { throw RecipeError.modelMismatch }
        var records: [FileState] = []
        while let url = enumerator.nextObject() as? URL {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard info.isSymbolicLink != true else { throw RecipeError.modelMismatch }
            if info.isRegularFile == true {
                records.append(.init(path: try ModelAssetPath.relativePath(url, root: root), bytes: info.fileSize ?? 0,
                                     modified: info.contentModificationDate?.timeIntervalSince1970 ?? 0))
            }
        }
        return try canonicalDigest(records.sorted { $0.path < $1.path })
    }
    static func inspectedImageWidth(at root: URL, family: PipelineFamily) throws -> Int {
        if family == .flux2Klein4B { try CoreAIFluxAssets.validate(at: root, verifyHashes: false); return 512 }
        if family == .sanaSprint06B { return 512 }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let names = ["Unet.mlmodelc", "UnetChunk1.mlmodelc"]
        guard let unet = names.first(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) else {
            throw RecipeError.modelMismatch
        }
        let latentShape: [Int] = try autoreleasepool {
            let model = try MLModel(contentsOf: root.appendingPathComponent(unet), configuration: config)
            let required = family == .sdxl
                ? ["sample", "timestep", "encoder_hidden_states", "text_embeds", "time_ids"]
                : ["sample", "timestep", "encoder_hidden_states"]
            guard required.allSatisfy({ model.modelDescription.inputDescriptionsByName[$0]?.multiArrayConstraint != nil }) else {
                throw RecipeError.invalid("UNetの入力形状に対応していません。")
            }
            guard let shape = model.modelDescription.inputDescriptionsByName["sample"]?.multiArrayConstraint?.shape else {
                throw RecipeError.invalid("UNetの入力形状を確認できません。")
            }
            return shape.map { $0.intValue }
        }
        let decoderShapes: (input: [Int], output: [Int]) = try autoreleasepool {
            let decoder = try MLModel(contentsOf: root.appendingPathComponent("VAEDecoder.mlmodelc"), configuration: config)
            let inputs = decoder.modelDescription.inputDescriptionsByName
            let outputs = decoder.modelDescription.outputDescriptionsByName
            guard inputs.count == 1, outputs.count == 1,
                  let input = inputs.values.first?.multiArrayConstraint?.shape,
                  let output = outputs.values.first?.multiArrayConstraint?.shape else {
                throw RecipeError.invalid("decoderの入出力形状を確認できません。")
            }
            return (input.map { $0.intValue }, output.map { $0.intValue })
        }
        let width = try DiffusionModelShapes.imageWidth(unet: latentShape,
            decoderInput: decoderShapes.input, decoderOutput: decoderShapes.output)
        if family == .sdxl {
            for name in ["TextEncoder.mlmodelc", "TextEncoder2.mlmodelc"] {
                try autoreleasepool {
                    let encoder = try MLModel(contentsOf: root.appendingPathComponent(name), configuration: config)
                    guard encoder.modelDescription.inputDescriptionsByName["input_ids"]?.multiArrayConstraint?.shape.last?.intValue == 77 else {
                        throw RecipeError.invalid("SDXLのtext encoder形式に対応していません。")
                    }
                    guard ["hidden_embeds", "pooled_outputs"].allSatisfy({
                        encoder.modelDescription.outputDescriptionsByName[$0]?.multiArrayConstraint != nil
                    }) else { throw RecipeError.invalid("SDXLのtext encoder形式に対応していません。") }
                }
            }
        }
        return width
    }

    static func requiredFilesExist(at root: URL, family: PipelineFamily) -> Bool {
        if family == .flux2Klein4B { return CoreAIFluxAssets.installed(at: root) }
        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(path).path) }
        if family == .sanaSprint06B {
            return ["SanaTextEncoder.mlmodelc", "SanaTransformer.mlmodelc", "SanaVAEDecoder.mlmodelc",
                    "tokenizer/tokenizer.json", "tokenizer/tokenizer_config.json"].allSatisfy(exists)
        }
        return exists("TextEncoder.mlmodelc") && exists("VAEDecoder.mlmodelc") &&
            exists("merges.txt") && exists("vocab.json") &&
            (exists("Unet.mlmodelc") || (exists("UnetChunk1.mlmodelc") && exists("UnetChunk2.mlmodelc"))) &&
            (family != .sdxl || exists("TextEncoder2.mlmodelc"))
    }

    static func manifest(at root: URL, modelID: String, revision: String, family: PipelineFamily, width: Int) throws -> ModelAssetManifest {
        guard requiredFilesExist(at: root, family: family) else {
            throw RecipeError.invalid("モデル資産が不足しています。tokenizer・text encoder・UNet・decoderを確認してください。")
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                                            options: [.skipsHiddenFiles]) else { throw RecipeError.modelMismatch }
        var files: [ModelAssetFile] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw RecipeError.invalid("モデル資産にリンクを含められません。") }
            guard values.isRegularFile == true else { continue }
            let relative = try ModelAssetPath.relativePath(url, root: root)
            guard !["model.zip", "model.zip.part", "mim-manifest.json"].contains(relative) else { continue }
            let bytes = values.fileSize ?? 0
            guard bytes > 0 else { continue }
            files.append(.init(path: relative, sha256: try fileSHA256(at: url), bytes: Int64(bytes)))
        }
        let result = ModelAssetManifest(schemaVersion: 1, modelID: modelID, revision: revision, family: family,
                                        width: width, height: width, files: files.sorted { $0.path < $1.path })
        try result.validate()
        return result
    }

    static func fileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while try autoreleasepool(invoking: { () throws -> Bool in
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { return false }
            // FileHandle bridges NSData; drain each chunk rather than retaining a multi-GB file.
            hash.update(data: data)
            return true
        }) {}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
