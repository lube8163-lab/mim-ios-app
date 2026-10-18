import UIKit

struct PhotoUnderstandingOutput {
    let scene: PhotoSceneDescription
    let identity: StageModelIdentity
    let processedSize: CGSize
    let measurements: StageMeasurements
    var fallbackReason: String? = nil
}

struct PhotoGenerationOutput {
    let image: UIImage
    let identity: StageModelIdentity
    let measurements: StageMeasurements
}

@MainActor
protocol PhotoUnderstandingProvider {
    var identity: StageModelIdentity { get }
    var availability: ProviderAvailability { get }
    func analyze(_ image: UIImage) async throws -> PhotoUnderstandingOutput
}

@MainActor
protocol PhotoGenerationProvider {
    var availability: ProviderAvailability { get }
    func render(_ recipe: GenerationRecipe, seed: UInt32) async throws -> PhotoGenerationOutput
}

struct FoundationUnderstandingProvider: PhotoUnderstandingProvider {
    var identity: StageModelIdentity { .foundationBaseline }
    var availability: ProviderAvailability {
        let state = FoundationPhotoUnderstandingService.availability
        return .init(status: state.canAnalyze ? .ready : .unavailable, message: state.message)
    }
    func analyze(_ image: UIImage) async throws -> PhotoUnderstandingOutput {
        try availability.requireReady()
        return try await FoundationPhotoUnderstandingService.analyzeMeasured(image)
    }
}

struct CoreAIUnderstandingProvider: PhotoUnderstandingProvider {
    var identity: StageModelIdentity { CoreAIPhotoUnderstandingService.identity }
    var availability: ProviderAvailability { CoreAIPhotoUnderstandingService.availability }
    func analyze(_ image: UIImage) async throws -> PhotoUnderstandingOutput {
        try availability.requireReady()
        return try await CoreAIPhotoUnderstandingService.analyze(image)
    }
}

struct CoreAIPreferredUnderstandingProvider: PhotoUnderstandingProvider {
    var identity: StageModelIdentity { CoreAIPhotoUnderstandingService.identity }
    var availability: ProviderAvailability {
        let primary = CoreAIUnderstandingProvider().availability
        return primary.canRun ? primary : FoundationUnderstandingProvider().availability
    }
    func analyze(_ image: UIImage) async throws -> PhotoUnderstandingOutput {
        let primary = CoreAIUnderstandingProvider()
        let fallback = FoundationUnderstandingProvider()
        let output = try await UnderstandingFallback.run(primaryAvailability: primary.availability,
            fallbackAvailability: fallback.availability,
            primary: { try await primary.analyze(image) }, fallback: { try await fallback.analyze(image) })
        var result = output.result
        result.fallbackReason = output.reason
        return result
    }
}

struct CoreMLGenerationProvider: PhotoGenerationProvider {
    var availability: ProviderAvailability {
        .init(status: ModelManager.shared.sdInstalled ? .ready : .missingAssets, message: "Core ML再現モデルの準備が必要です。")
    }
    func render(_ recipe: GenerationRecipe, seed: UInt32) async throws -> PhotoGenerationOutput {
        try availability.requireReady()
        return try await RecipeImageRenderer.shared.renderMeasured(recipe, seed: seed)
    }
}

struct CoreAIGenerationProvider: PhotoGenerationProvider {
    var availability: ProviderAvailability {
        guard CoreAIFluxAssets.runtimeSupported else {
            return .init(status: .unsupportedRuntime, message: "画像の再現にはiOS 27.0.1以降・RAM 8 GB以上の対応端末が必要です。")
        }
        return .init(status: ModelManager.shared.isSDModelInstalled(ModelManager.fluxModelID) ? .ready : .missingAssets,
                     message: "FLUX.2 Kleinの準備が必要です。")
    }
    func render(_ recipe: GenerationRecipe, seed: UInt32) async throws -> PhotoGenerationOutput {
        try availability.requireReady()
        guard recipe.model.family == .flux2Klein4B else { throw RecipeError.modelMismatch }
        return try await RecipeImageRenderer.shared.renderMeasured(recipe, seed: seed)
    }
}

enum PhotoProviderRegistry {
    static func understanding(_ id: UnderstandingProviderID) -> any PhotoUnderstandingProvider {
        switch id {
        case .foundationModels: return FoundationUnderstandingProvider()
        case .coreAIVLM: return CoreAIPreferredUnderstandingProvider()
        }
    }
    static func generation(_ id: GenerationProviderID) -> any PhotoGenerationProvider {
        switch id {
        case .coreML: return CoreMLGenerationProvider()
        case .coreAI: return CoreAIGenerationProvider()
        }
    }
}
