//
//  ImageGenerator.swift
//  SemanticCompressionApp
//

import Foundation
import CoreML
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

        let pipe = try StableDiffusionPipeline(
            resourcesAt: modelsDirectory,
            controlNet: [],
            reduceMemory: false   // メモリ削減モード
        )

        try pipe.loadResources()
        self.pipeline = pipe

        #if DEBUG
        print("✅ Stable Diffusion pipeline loaded from Application Support")
        #endif
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
