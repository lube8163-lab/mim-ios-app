//
//  ImageGenerator.swift
//  SemanticCompressionApp
//

import Foundation
import UIKit
import StableDiffusion

actor ImageGenerator {

    // ✅ actor のプロパティとして保持
    private var pipeline: StableDiffusionPipeline?

    // MARK: - Initializer

    init(modelsDirectory: URL) throws {
        #if DEBUG
        print("🧠 Loading Stable Diffusion from:", modelsDirectory.path)
        #endif

        try Self.ensureTokenizerFiles(at: modelsDirectory)
        try Self.ensureCoreMLModelFiles(at: modelsDirectory)

        let pipe = try StableDiffusionPipeline(
            resourcesAt: modelsDirectory,
            controlNet: [],
            reduceMemory: true
        )

        try pipe.loadResources()
        self.pipeline = pipe

        #if DEBUG
        print("✅ Stable Diffusion pipeline loaded from Application Support")
        #endif
    }

    private static func ensureTokenizerFiles(at modelsDirectory: URL) throws {
        let fm = FileManager.default

        let rootMerges = modelsDirectory.appendingPathComponent("merges.txt")
        let rootVocab = modelsDirectory.appendingPathComponent("vocab.json")
        let tokenizerDir = modelsDirectory.appendingPathComponent("tokenizer", isDirectory: true)

        if fm.fileExists(atPath: rootMerges.path),
           fm.fileExists(atPath: rootVocab.path) {
            return
        }

        let stableDiffusionRoot = modelsDirectory.deletingLastPathComponent()
        let siblingDirs = (try? fm.contentsOfDirectory(
            at: stableDiffusionRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.path != modelsDirectory.path } ?? []

        var searchRoots: [URL] = [modelsDirectory, tokenizerDir]
        for sibling in siblingDirs {
            searchRoots.append(sibling)
            searchRoots.append(sibling.appendingPathComponent("tokenizer", isDirectory: true))
        }

        func firstExisting(_ fileName: String) -> URL? {
            for root in searchRoots {
                let candidate = root.appendingPathComponent(fileName)
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }

        if !fm.fileExists(atPath: rootMerges.path),
           let src = firstExisting("merges.txt") {
            try? fm.removeItem(at: rootMerges)
            try fm.copyItem(at: src, to: rootMerges)
        }

        if !fm.fileExists(atPath: rootVocab.path),
           let src = firstExisting("vocab.json") {
            try? fm.removeItem(at: rootVocab)
            try fm.copyItem(at: src, to: rootVocab)
        }

        guard fm.fileExists(atPath: rootMerges.path),
              fm.fileExists(atPath: rootVocab.path) else {
            throw NSError(
                domain: "ImageGenerator",
                code: -31,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Tokenizer files are missing. Please include merges.txt and vocab.json in the model package root (or tokenizer/)."
                ]
            )
        }
    }

    private static func ensureCoreMLModelFiles(at modelsDirectory: URL) throws {
        let fm = FileManager.default

        func hasModel(_ name: String) -> Bool {
            fm.fileExists(atPath: modelsDirectory.appendingPathComponent(name).path)
        }

        let hasUNet = hasModel("Unet.mlmodelc")
            || (hasModel("UnetChunk1.mlmodelc") && hasModel("UnetChunk2.mlmodelc"))
            || (hasModel("UNetChunk1.mlmodelc") && hasModel("UNetChunk2.mlmodelc"))
        let hasTextEncoder = hasModel("TextEncoder.mlmodelc")
        let hasVAEEncoder = hasModel("VAEEncoder.mlmodelc")
        let hasVAEDecoder = hasModel("VAEDecoder.mlmodelc")

        if hasUNet && hasTextEncoder && hasVAEEncoder && hasVAEDecoder {
            return
        }
        throw NSError(
            domain: "ImageGenerator",
            code: -32,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Core ML model files are missing. Expected Unet.mlmodelc or UnetChunk1/UnetChunk2, plus TextEncoder/VAEEncoder/VAEDecoder .mlmodelc files."
            ]
        )
    }

    // MARK: - Image Generation

    func generateImage(
        from prompt: String,
        negativePrompt: String = "",
        initImage: UIImage? = nil,
        strength: Float = 0.6,
        steps: Int = 25,
        guidance: Float = 8.5,
        seed: UInt32? = nil
    ) async throws -> UIImage {

        guard let pipeline = self.pipeline else {
            throw NSError(
                domain: "ImageGenerator",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Stable Diffusion pipeline not loaded"]
            )
        }

        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negativePrompt
        config.stepCount = steps
        config.guidanceScale = guidance
        config.seed = seed ?? UInt32.random(in: 0...UInt32.max)
        if let initImage, let cg = initImage.cgImage {
            let w = cg.width
            let h = cg.height
            let isValidSize = (w % 64 == 0) && (h % 64 == 0)
            if isValidSize {
                config.startingImage = cg
                config.strength = max(0.0, min(1.0, strength))
                #if DEBUG
                print("🖼️ initImage size:", w, "x", h, "strength:", config.strength)
                #endif
            } else {
                #if DEBUG
                print("⚠️ initImage size not supported:", w, "x", h)
                #endif
            }
        }

        #if DEBUG
        print("🎨 Generating image with prompt:", prompt)
        #endif
        
        let cgImages: [CGImage?] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try pipeline.generateImages(configuration: config)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard let cg = cgImages.first ?? nil else {
            throw NSError(
                domain: "ImageGenerator",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No image generated"]
            )
        }

        #if DEBUG
        print("✅ Image generated successfully")
        #endif
        return UIImage(cgImage: cg)
    }

    // MARK: - Cleanup

    func unloadResources() async {
        guard let pipeline = self.pipeline else { return }

        DispatchQueue.global(qos: .utility).async {
            pipeline.unloadResources()
            #if DEBUG
            print("🧹 Stable Diffusion resources unloaded")
            #endif
        }

        self.pipeline = nil
    }
}
