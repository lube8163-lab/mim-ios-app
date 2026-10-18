import Foundation
import CryptoKit

nonisolated enum RecipeError: Error, LocalizedError, Equatable {
    case invalid(String)
    case unsupported(String)
    case modelMismatch
    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unsupported(let message): return message
        case .modelMismatch: return "この投稿と同じモデル資産の準備が必要です。"
        }
    }
}

nonisolated enum PipelineFamily: String, Codable, Sendable { case sd15, sdxl, sanaSprint06B, flux2Klein4B }

nonisolated struct ModelAssetFile: Codable, Equatable, Sendable {
    let path: String
    let sha256: String
    let bytes: Int64
}

nonisolated struct ModelAssetManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let modelID: String
    let revision: String
    let family: PipelineFamily
    let width: Int
    let height: Int
    let files: [ModelAssetFile]

    var identity: String { get throws { try canonicalDigest(self) } }

    var normalizedForComparison: Self {
        let prefix = "on/sd15/"
        guard modelID == "sd15", revision == "coreml-v2", family == .sd15,
              !files.isEmpty, files.allSatisfy({ $0.path.hasPrefix(prefix) }) else { return self }
        return .init(schemaVersion: schemaVersion, modelID: modelID, revision: revision, family: family,
            width: width, height: height, files: files.map {
                .init(path: String($0.path.dropFirst(prefix.count)), sha256: $0.sha256, bytes: $0.bytes)
            })
    }

    func validate() throws {
        guard schemaVersion == 1, !modelID.isEmpty, !revision.isEmpty,
              width == height, [512, 768, 1024].contains(width), !files.isEmpty else {
            throw RecipeError.invalid("モデルmanifestが無効です。")
        }
        guard family != .sanaSprint06B || width == 512 else {
            throw RecipeError.unsupported("Sana Sprint 0.6Bは512px専用です。")
        }
        guard family != .flux2Klein4B || width == 512 else {
            throw RecipeError.unsupported("FLUX.2 Kleinは512px専用です。")
        }
        guard Set(files.map(\.path)).count == files.count else {
            throw RecipeError.invalid("モデルmanifestに重複したファイルがあります。")
        }
        for file in files {
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains(".."),
                  !file.path.isEmpty, file.bytes > 0,
                  file.sha256.count == 64, file.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw RecipeError.invalid("モデルmanifestのファイル記述が無効です。")
            }
        }
    }
}

nonisolated struct GenerationRecipe: Codable, Equatable, Sendable {
    enum SeedPolicy: String, Codable, Sendable { case viewerRandom }
    static let pipelineVersion = "mim-coreml-t2i-v1"
    static let promptFormatVersion = "scene-en-v1"
    static let fluxPipelineVersion = "mim-coreai-flux2-t2i-v1"
    static let fluxPromptFormatVersion = "scene-en-flux2-v1"
    let version: Int
    let prompt: String
    let negativePrompt: String
    let model: ModelAssetManifest
    let pipelineVersion: String
    let promptFormatVersion: String
    let safetyPolicyIdentity: String
    let seed: UInt32?
    let width: Int
    let height: Int
    let scheduler: String
    let steps: Int
    let guidance: Float
    var seedPolicy: SeedPolicy? = nil

    var cacheKey: String { get throws { "recipe-v\(version):" + (try canonicalDigest(self)) } }

    func renderCacheKey(seed: UInt32) throws -> String {
        if version == 1 { return try cacheKey }
        return "viewer-image-v2:" + (try canonicalDigest(RenderIdentity(recipe: self, seed: seed)))
    }

    private struct RenderIdentity: Encodable { let recipe: GenerationRecipe; let seed: UInt32 }

    static func photo(prompt: String, manifest: ModelAssetManifest, safetyPolicyIdentity: String) -> Self {
        let flux = manifest.family == .flux2Klein4B
        let sana = manifest.family == .sanaSprint06B
        return .init(version: 2, prompt: prompt, negativePrompt: flux || sana ? "" : ScenePromptBuilder.sdNegativePrompt,
            model: manifest, pipelineVersion: flux ? fluxPipelineVersion : pipelineVersion,
            promptFormatVersion: flux ? fluxPromptFormatVersion : promptFormatVersion,
            safetyPolicyIdentity: safetyPolicyIdentity, seed: nil, width: manifest.width, height: manifest.height,
            scheduler: flux ? "discreteFlow" : (sana ? "scm-trigflow" : "dpmSolverMultistep"),
            steps: flux ? 4 : (sana ? 2 : 25), guidance: flux ? 1 : (sana ? 4.5 : 7.5), seedPolicy: .viewerRandom)
    }

    func validate(installedManifest: ModelAssetManifest? = nil) throws {
        let isFlux = model.family == .flux2Klein4B
        guard [1, 2].contains(version), pipelineVersion == (isFlux ? Self.fluxPipelineVersion : Self.pipelineVersion),
              promptFormatVersion == (isFlux ? Self.fluxPromptFormatVersion : Self.promptFormatVersion),
              !isFlux || version == 2 else {
            throw RecipeError.unsupported("この投稿の再現形式にはまだ対応していません。")
        }
        guard version == 1 ? (seed != nil && seedPolicy == nil) : (seed == nil && seedPolicy == .viewerRandom) else {
            throw RecipeError.invalid("画像のランダム設定が無効です。")
        }
        try model.validate()
        // This runs before cache lookup too, so a legacy cached image cannot bypass
        // the current prompt policy. Serialized recipe identities remain unchanged.
        try ContentSafetyPolicy.bundled().validate(prompt, context: .generationPrompt)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "simple scene", prompt.count <= 2000,
              negativePrompt.count <= 2000, width == model.width, height == model.height,
              safetyPolicyIdentity.count == 64, safetyPolicyIdentity.allSatisfy({ "0123456789abcdef".contains($0) }),
              guidance.isFinite, guidance >= 0, guidance <= 20 else {
            throw RecipeError.invalid("写真の説明または再現設定が無効です。")
        }
        let isSana = model.family == .sanaSprint06B
        guard scheduler == (isFlux ? "discreteFlow" : (isSana ? "scm-trigflow" : "dpmSolverMultistep")),
              !(isSana || isFlux) || negativePrompt.isEmpty,
              isFlux ? (steps == 4 && guidance == 1) : (isSana ? (1...2).contains(steps) : (1...60).contains(steps)) else {
            throw RecipeError.unsupported("この再現設定には対応していません。")
        }
        if let installedManifest {
            try installedManifest.validate()
            // Compare the actual asset names. Some earlier iOS recipes included
            // a /var vs /private/var offset in every SD15 path; their serialized
            // identities stay intact for existing server records and caches.
            let expected = model.normalizedForComparison
            let installed = installedManifest.normalizedForComparison
            try expected.validate()
            try installed.validate()
            guard try installed.identity == expected.identity else { throw RecipeError.modelMismatch }
        }
    }
}

nonisolated func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

nonisolated func canonicalDigest<T: Encodable>(_ value: T) throws -> String {
    SHA256.hash(data: try canonicalData(value)).map { String(format: "%02x", $0) }.joined()
}

// This allowlisted DTO has no image or latent payload field.
nonisolated struct PostUploadPayload: Encodable, Sendable {
    let mode: Int = 1
    let caption: String?
    let semanticPrompt: String?
    let tags: [String]
    let imageUnderstandingBackend: String?
    let userText: String?
    let hasImage: Bool
    let recipe: GenerationRecipe?
}

nonisolated struct RecipeServerCapabilities: Codable, Sendable {
    let promptOnlyRecipeVersions: [Int]
    var backgroundPhotoPosts: Bool? = nil
    var supportsV1: Bool { promptOnlyRecipeVersions.contains(1) }
    func supports(_ version: Int) -> Bool { promptOnlyRecipeVersions.contains(version) }
}

nonisolated enum PhotoUnderstandingAvailability: Equatable, Sendable {
    case available, unsupportedDevice, intelligenceDisabled, preparing, unavailable
    var canAnalyze: Bool { self == .available }
    var message: String {
        switch self {
        case .available: return "写真を理解する準備ができています"
        case .unsupportedDevice: return "iOS 27以降・RAM 8 GB以上の対応iPhoneが必要です"
        case .intelligenceDisabled: return "設定でApple Intelligenceを有効にしてください"
        case .preparing: return "Apple Intelligenceの準備中です"
        case .unavailable: return "写真の理解を利用できません。あとで再試行してください"
        }
    }
}
