import Foundation

nonisolated enum UnderstandingProviderID: String, Codable, CaseIterable, Sendable {
    case foundationModels, coreAIVLM
    var title: String {
        switch self {
        case .foundationModels: return "Apple Foundation Models"
        case .coreAIVLM: return "CoreAI / Apple Foundation Models"
        }
    }
}

nonisolated enum GenerationProviderID: String, Codable, CaseIterable, Sendable {
    case coreML, coreAI
    var title: String { self == .coreML ? "Core ML (baseline)" : "CoreAI" }
}

nonisolated struct ProviderAvailability: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case ready, unavailable, missingAssets, runnerNotImplemented, unsupportedRuntime }
    let status: Status
    let message: String
    var canRun: Bool { status == .ready }
    func requireReady() throws {
        guard canRun else { throw RecipeError.unsupported(message) }
    }
    static func coreAI(sdkAvailable: Bool, assetsAvailable: Bool = false, runnerImplemented: Bool = false) -> Self {
        if !sdkAvailable { return .init(status: .unsupportedRuntime, message: "この実行環境にはCoreAI runtimeがありません。") }
        if !assetsAvailable { return .init(status: .missingAssets, message: "CoreAIモデル資産が未導入です。") }
        if !runnerImplemented { return .init(status: .runnerNotImplemented, message: "CoreAI推論runnerは未実装です。") }
        return .init(status: .ready, message: "準備済み")
    }
}

nonisolated struct StageModelIdentity: Codable, Equatable, Sendable {
    let modelID: String
    let modelRevision: String?
    let runtime: String
    let runtimeVersion: String?
    let assetManifestSHA256: String?
    static let foundationBaseline = Self(modelID: "apple/SystemLanguageModel.default", modelRevision: nil,
                                         runtime: "FoundationModels", runtimeVersion: nil, assetManifestSHA256: nil)
    static let unconfiguredCoreAI = Self(modelID: "unconfigured", modelRevision: nil, runtime: "CoreAI",
                                         runtimeVersion: nil, assetManifestSHA256: nil)
    static func coreML(_ manifest: ModelAssetManifest) throws -> Self {
        .init(modelID: manifest.modelID, modelRevision: manifest.revision, runtime: "CoreML", runtimeVersion: nil,
              assetManifestSHA256: try manifest.identity)
    }
    static func generation(_ manifest: ModelAssetManifest) throws -> Self {
        .init(modelID: manifest.modelID, modelRevision: manifest.revision,
              runtime: manifest.family == .flux2Klein4B ? "CoreAI" : "CoreML",
              runtimeVersion: manifest.family == .flux2Klein4B ? "mim-flux2-v1" : nil,
              assetManifestSHA256: try manifest.identity)
    }
    enum CodingKeys: String, CodingKey { case modelID, modelRevision, runtime, runtimeVersion, assetManifestSHA256 }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelID, forKey: .modelID); try c.encode(modelRevision, forKey: .modelRevision)
        try c.encode(runtime, forKey: .runtime); try c.encode(runtimeVersion, forKey: .runtimeVersion)
        try c.encode(assetManifestSHA256, forKey: .assetManifestSHA256)
    }
}

nonisolated struct StageMeasurements: Codable, Equatable, Sendable {
    var preparationSeconds: Double? = nil
    var inferenceSeconds: Double? = nil
    var elapsedSeconds: Double? = nil
    var elapsedScope: String? = nil
    var peakMemoryBytes: UInt64? = nil
    var peakMemoryMethod: String? = nil
    var memoryScope: String? = nil
    var samplingIntervalMilliseconds: Double? = nil

    func validate() throws {
        for value in [preparationSeconds, inferenceSeconds, elapsedSeconds, samplingIntervalMilliseconds].compactMap({ $0 }) {
            guard value.isFinite, value >= 0 else { throw RecipeError.invalid("計測値が無効です。") }
        }
        if peakMemoryBytes != nil {
            guard let peakMemoryMethod, !peakMemoryMethod.isEmpty, let memoryScope, !memoryScope.isEmpty else {
                throw RecipeError.invalid("ピークメモリの計測方法と対象が必要です。")
            }
            if peakMemoryMethod == "sampling" {
                guard let samplingIntervalMilliseconds, samplingIntervalMilliseconds > 0 else {
                    throw RecipeError.invalid("メモリsamplingの間隔が必要です。")
                }
            }
        }
    }
    enum CodingKeys: String, CodingKey {
        case preparationSeconds, inferenceSeconds, elapsedSeconds, elapsedScope
        case peakMemoryBytes, peakMemoryMethod, memoryScope, samplingIntervalMilliseconds
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preparationSeconds, forKey: .preparationSeconds); try c.encode(inferenceSeconds, forKey: .inferenceSeconds)
        try c.encode(elapsedSeconds, forKey: .elapsedSeconds); try c.encode(elapsedScope, forKey: .elapsedScope)
        try c.encode(peakMemoryBytes, forKey: .peakMemoryBytes); try c.encode(peakMemoryMethod, forKey: .peakMemoryMethod)
        try c.encode(memoryScope, forKey: .memoryScope); try c.encode(samplingIntervalMilliseconds, forKey: .samplingIntervalMilliseconds)
    }
}

nonisolated struct StageEnvironment: Codable, Equatable, Sendable {
    enum Target: String, Codable, Sendable { case physicalDevice, simulator, windowsGPU, windowsCPU, mac }
    let deviceModel: String
    let osVersion: String
    let executionTarget: Target
}

nonisolated struct MimStageEvidence<Input: Codable & Sendable, Result: Codable & Sendable>: Codable, Sendable {
    enum Stage: String, Codable, Sendable { case understanding, generation }
    enum Status: String, Codable, Sendable { case completed, failed, cancelled, notRun }
    var schemaVersion = 1
    var kind = "MimStageEvidence"
    let stage: Stage
    let caseID: String
    var status: Status
    let sourceSHA256: String
    let identity: StageModelIdentity
    let environment: StageEnvironment
    var measurements: StageMeasurements
    let input: Input
    var result: Result
    var settings: GenerationEvidenceSettings? = nil
    let recordedAt: String
    var fallbackReason: String? = nil
    var requestedUnderstandingProvider: UnderstandingProviderID? = nil
}

nonisolated struct UnderstandingEvidenceInput: Codable, Sendable {
    let processedWidth: Int?
    let processedHeight: Int?
    let preprocessingVersion: String
    let processedSHA256: String?
    let instructionVersion: String
}

nonisolated struct UnderstandingEvidenceResult: Codable, Sendable {
    let prompt: String?
    let caption: String?
    let observations: [String]?
    let uncertainties: [String]?
    var editedPrompt: String?
}

nonisolated struct GenerationEvidenceInput: Codable, Sendable {
    enum PromptSource: String, Codable, Sendable { case manual, rawUnderstanding, editedUnderstanding }
    let prompt: String
    let negativePrompt: String
    let promptSource: PromptSource
    let understandingRecordSHA256: String?
}

nonisolated struct GenerationEvidenceSettings: Codable, Sendable {
    let seed: UInt32
    let width: Int
    let height: Int
    let scheduler: String
    let steps: Int
    let guidance: Float
    let pipelineVersion: String
}

nonisolated struct GenerationEvidenceResult: Codable, Sendable {
    let imageSHA256: String?
    enum CodingKeys: String, CodingKey { case imageSHA256 }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(imageSHA256, forKey: .imageSHA256)
    }
}

typealias UnderstandingStageEvidence = MimStageEvidence<UnderstandingEvidenceInput, UnderstandingEvidenceResult>
typealias GenerationStageEvidence = MimStageEvidence<GenerationEvidenceInput, GenerationEvidenceResult>

nonisolated struct MimComparisonRecord<Scene: Codable & Sendable>: Codable, Sendable {
    let version: Int
    let sourceID: String
    let understandingBackend: String
    let sourceSHA256: String
    let osVersion: String
    let deviceModel: String
    let processedWidth: Int?
    let processedHeight: Int?
    let understandingElapsedSeconds: Double?
    let scene: Scene?
    let recipe: GenerationRecipe?
    let editedPrompt: String
    let understandingRecord: UnderstandingStageEvidence?
    let generationRecord: GenerationStageEvidence
}
