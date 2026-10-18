import Foundation
import UIKit
#if canImport(CoreAI) && !targetEnvironment(simulator)
import CoreAIDiffusionPipeline
#endif

nonisolated final class FluxGenerationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var step: Int { lock.lock(); defer { lock.unlock() }; return value }
    func update(_ step: Int) { lock.lock(); value = step; lock.unlock() }
}

/// Retains only tokenizer/CPU conditioning between calls; GPU weights are always released.
#if canImport(CoreAI) && !targetEnvironment(simulator)
actor FluxImageGenerator {
    private let manifest: ModelAssetManifest
    private let pipeline: FlowTransformerPipeline
    private var checkpoint: FlowTransformerPipeline.GenerationCheckpoint?
    nonisolated let progress = FluxGenerationProgress()

    init(directory: URL, manifest: ModelAssetManifest) async throws {
        self.manifest = manifest
        pipeline = try await FlowTransformerPipeline(from: directory, mode: .half)
    }
    func generate(recipe: GenerationRecipe, seed: UInt32, cancellation: GenerationCancellation) async throws -> UIImage {
        try recipe.validate(installedManifest: manifest)
        let configuration = CoreAIDiffusionPipeline.PipelineConfiguration(prompt: recipe.prompt, seed: seed,
            stepCount: 4, guidanceScale: 1, schedulerType: .discreteFlow, decodeResolution: .half, lazyModelLoading: true)
        let resume = checkpoint
        checkpoint = nil
        if resume == nil { progress.update(0) }
        let progressState = progress
        do {
            let result = try await pipeline.generateResumable(configuration: configuration, resume: resume,
                shouldContinueBeforeDenoising: { cancellation.continueAfterStep(isLastStep: false) }) { progress in
                progressState.update(progress.step)
                return cancellation.continueAfterStep(isLastStep: progress.step == progress.totalSteps)
            }
            await pipeline.unloadResources()
            try Task.checkCancellation()
            guard let image = result.images.first, image.width == 512, image.height == 512 else {
                throw RecipeError.modelMismatch
            }
            return UIImage(cgImage: image)
        } catch let pause as FlowTransformerPipeline.GenerationPaused {
            await pipeline.unloadResources()
            try Task.checkCancellation()
            checkpoint = pause.checkpoint
            throw GenerationYieldToPhoto()
        } catch {
            checkpoint = nil
            await pipeline.unloadResources()
            throw error
        }
    }
    func discard() async {
        checkpoint = nil
        await pipeline.unloadResources()
    }
}
#else
actor FluxImageGenerator {
    nonisolated let progress = FluxGenerationProgress()
    init(directory: URL, manifest: ModelAssetManifest) async throws {
        throw RecipeError.unsupported("この環境はCoreAI画像生成に対応していません。")
    }
    func generate(recipe: GenerationRecipe, seed: UInt32, cancellation: GenerationCancellation) async throws -> UIImage {
        throw RecipeError.unsupported("この環境はCoreAI画像生成に対応していません。")
    }
    func discard() async {}
}
#endif
