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
            reduceMemory: true   // メモリ削減モード
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
        steps: Int = 15,
        guidance: Float = 7.5
    ) async throws -> UIImage {

        guard let pipeline = self.pipeline else {
            throw NSError(
                domain: "ImageGenerator",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Stable Diffusion pipeline not loaded"]
            )
        }

        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.stepCount = steps
        config.guidanceScale = guidance
        config.seed = UInt32.random(in: 0...UInt32.max)

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
