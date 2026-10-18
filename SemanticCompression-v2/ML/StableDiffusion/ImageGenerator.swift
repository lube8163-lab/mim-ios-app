import Foundation
import CoreML
import UIKit
import StableDiffusion
import Tokenizers

nonisolated final class GenerationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var photoPending = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var shouldYield: Bool { lock.lock(); defer { lock.unlock() }; return photoPending && !cancelled }
    private var yielded = false
    var didYield: Bool { lock.lock(); defer { lock.unlock() }; return yielded }
    func continueAfterStep(isLastStep: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        if photoPending && !isLastStep { yielded = true; return false }
        return true
    }
    func yieldToPhoto() { lock.lock(); photoPending = true; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

nonisolated struct GenerationYieldToPhoto: Error {}

actor ImageGenerator {
    private let manifest: ModelAssetManifest
    private let resources: URL
    private var sd: (any StableDiffusionPipelineProtocol)?
    private var sana: SanaImageGenerator?

    init(modelsDirectory: URL, manifest: ModelAssetManifest) throws {
        try manifest.validate()
        self.manifest = manifest
        self.resources = modelsDirectory
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        switch manifest.family {
        case .flux2Klein4B: throw RecipeError.unsupported("FLUXはCoreAIで処理します。")
        case .sanaSprint06B: sana = try SanaImageGenerator(resourcesURL: modelsDirectory)
        case .sd15:
            sd = try StableDiffusionPipeline(resourcesAt: modelsDirectory, controlNet: [], configuration: config, reduceMemory: true)
        case .sdxl:
            sd = try StableDiffusionXLPipeline(resourcesAt: modelsDirectory, configuration: config, reduceMemory: true)
        }
    }

    func generateImage(recipe: GenerationRecipe, seed: UInt32, cancellation: GenerationCancellation) async throws -> UIImage {
        try recipe.validate(installedManifest: manifest)
        try Task.checkCancellation()
        if let sana {
            let result = try await sana.generate(prompt: recipe.prompt,
                                                 steps: recipe.steps, guidance: recipe.guidance, seed: seed)
            try Task.checkCancellation()
            return result
        }
        guard let sd else { throw RecipeError.modelMismatch }
        let tokenizer = try BPETokenizer(mergesAt: resources.appendingPathComponent("merges.txt"),
                                         vocabularyAt: resources.appendingPathComponent("vocab.json"))
        guard tokenizer.tokenize(input: recipe.prompt).tokenIDs.count <= 77,
              tokenizer.tokenize(input: recipe.negativePrompt).tokenIDs.count <= 77 else {
            throw RecipeError.invalid("写真の説明が長すぎます。主題と配置を残して短くしてください。")
        }
        var configuration = PipelineConfiguration(prompt: recipe.prompt)
        configuration.negativePrompt = recipe.negativePrompt
        configuration.seed = seed
        configuration.stepCount = recipe.steps
        configuration.guidanceScale = recipe.guidance
        configuration.schedulerType = .dpmSolverMultistepScheduler
        configuration.rngType = .numpyRNG
        configuration.originalSize = Float(recipe.width)
        configuration.targetSize = Float(recipe.width)
        if manifest.family == .sdxl {
            configuration.decoderScaleFactor = 0.13025
            configuration.encoderScaleFactor = 0.13025
        }
        if cancellation.shouldYield { throw GenerationYieldToPhoto() }
        let result: [CGImage?]
        do { result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    defer { sd.unloadResources() }
                    let progress: (StableDiffusionPipeline.Progress) -> Bool = { progress in
                        cancellation.continueAfterStep(isLastStep: progress.step >= progress.stepCount - 1)
                    }
                    if let sd15 = sd as? StableDiffusionPipeline {
                        return try sd15.generateImages(configuration: configuration, progressHandler: progress,
                            shouldContinue: { cancellation.continueAfterStep(isLastStep: false) })
                    }
                    return try sd.generateImages(configuration: configuration, progressHandler: progress)
                }
            }.value
        } onCancel: { cancellation.cancel() }
        } catch {
            try Task.checkCancellation()
            if cancellation.didYield { throw GenerationYieldToPhoto() }
            throw error
        }
        try Task.checkCancellation()
        if cancellation.didYield { throw GenerationYieldToPhoto() }
        guard let cgImage = result.first ?? nil else { throw RecipeError.invalid("画像を再現できませんでした。") }
        guard cgImage.width == recipe.width, cgImage.height == recipe.height else {
            throw RecipeError.invalid("モデルの出力解像度が再現設定と一致しません。")
        }
        return UIImage(cgImage: cgImage)
    }

    func unloadResources() { sd?.unloadResources(); sana?.unload() }
}

@MainActor
final class RecipeImageRenderer {
    static let shared = RecipeImageRenderer()
    private var busy = false
    private var fluxRunner: FluxImageGenerator?
    private var fluxIdentity: String?
    private var discardAfterUse = false
    private var memoryObserver: NSObjectProtocol?
    private(set) var completedYieldCount = 0
    var currentFluxStep: Int { fluxRunner?.progress.step ?? 0 }
    private init() {
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.discardFluxCache() }
            }
    }
    func discardFluxCache() async {
        if busy { discardAfterUse = true; return }
        busy = true
        defer { busy = false; discardAfterUse = false }
        await fluxRunner?.discard(); fluxRunner = nil; fluxIdentity = nil
    }
    func render(_ recipe: GenerationRecipe, seed: UInt32) async throws -> UIImage {
        try await renderMeasured(recipe, seed: seed).image
    }
    func renderMeasured(_ recipe: GenerationRecipe, seed: UInt32) async throws -> PhotoGenerationOutput {
        while busy {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
        }
        busy = true
        defer {
            busy = false
            if discardAfterUse { discardAfterUse = false; Task { await discardFluxCache() } }
        }
        try recipe.validate()
        let policy = try PromptPolicy.bundled()
        guard recipe.safetyPolicyIdentity == (try policy.identity) else {
            throw RecipeError.unsupported("この投稿の再現ポリシーには対応していません。")
        }
        try policy.validate(prompt: recipe.prompt)
        while true {
            do { return try await renderAttempt(recipe, seed: seed) }
            catch is GenerationYieldToPhoto {
                try Task.checkCancellation()
                completedYieldCount += 1
                // Keep the same recipe and viewer seed; the post gets the next model slot.
            }
            catch { await fluxRunner?.discard(); throw error }
        }
    }

    private func renderAttempt(_ recipe: GenerationRecipe, seed: UInt32) async throws -> PhotoGenerationOutput {
        let manager = ModelManager.shared
        try await manager.beginModelUseWhenAvailable()
        defer { manager.endModelUse() }
        let started = ProcessInfo.processInfo.systemUptime
        let directory = try manager.directory(for: recipe.model)
        let actual = try await manager.manifest(for: recipe.model.modelID)
        try recipe.validate(installedManifest: actual)
        try Task.checkCancellation()
        if actual.family == .flux2Klein4B {
            guard CoreAIFluxAssets.runtimeSupported else { throw RecipeError.unsupported("この端末はFLUX画像生成に対応していません。") }
            let identity = try actual.identity
            if fluxRunner == nil || fluxIdentity != identity {
                await fluxRunner?.discard()
                fluxRunner = try await FluxImageGenerator(directory: directory, manifest: actual)
                fluxIdentity = identity
            }
            guard let runner = fluxRunner else { throw RecipeError.modelMismatch }
            let cancellation = GenerationCancellation()
            manager.setGenerationYieldHandler { cancellation.yieldToPhoto() }
            defer { manager.setGenerationYieldHandler(nil) }
            let prepared = ProcessInfo.processInfo.systemUptime
            let image = try await withTaskCancellationHandler {
                try await runner.generate(recipe: recipe, seed: seed, cancellation: cancellation)
            } onCancel: { cancellation.cancel() }
            try Task.checkCancellation()
            try await ImageSafetyService.check(image)
            let finished = ProcessInfo.processInfo.systemUptime
            return .init(image: image, identity: try .generation(actual),
                measurements: .init(preparationSeconds: prepared - started, inferenceSeconds: finished - prepared,
                    elapsedSeconds: finished - started,
                    elapsedScope: "Pinned asset verification, CPU pipeline preparation, generation, GPU release and output safety. Excludes model queue wait and paused work."))
        }
        let runner = try ImageGenerator(modelsDirectory: directory, manifest: actual)
        let prepared = ProcessInfo.processInfo.systemUptime
        let cancellation = GenerationCancellation()
        if actual.family == .sd15 || actual.family == .sdxl {
            manager.setGenerationYieldHandler { cancellation.yieldToPhoto() }
        }
        defer { manager.setGenerationYieldHandler(nil) }
        do {
            let image = try await runner.generateImage(recipe: recipe, seed: seed, cancellation: cancellation)
            await runner.unloadResources()
            try await ImageSafetyService.check(image)
            let finished = ProcessInfo.processInfo.systemUptime
            return .init(image: image, identity: try .coreML(actual),
                         measurements: .init(preparationSeconds: prepared - started, inferenceSeconds: finished - prepared,
                                             elapsedSeconds: finished - started,
                                             elapsedScope: "Asset validation, runner construction, generation, resource release and generated-image safety classification. Includes lazy CoreML loading; excludes coordination queue wait and work discarded when yielding to a photo post."))
        } catch {
            await runner.unloadResources()
            throw error
        }
    }
}
