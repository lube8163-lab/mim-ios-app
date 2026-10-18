import CoreGraphics
import CoreML
import Foundation
import Tokenizers
import UIKit

/// Fixed-shape Core ML runner for Sana Sprint 0.6B at 512x512.
///
/// Text encoder, VAE and transformer are intentionally loaded one stage at a
/// time rather than retaining multiple large Core ML programs in memory.
/// The denoising update matches Diffusers' SCM/trig-flow schedule used
/// to distill Sana Sprint; it must not be run through the SD 1.5 scheduler.
nonisolated final class SanaImageGenerator: @unchecked Sendable {
    private let resourcesURL: URL
    private let queue = DispatchQueue(label: "SemanticCompression.Sana", qos: .userInitiated)
    private var tokenizer: (any Tokenizer)?

    private let imageSize = 512
    private let latentChannels = 32
    private let latentSize = 16
    private let textSequenceLength = 148
    private let promptSequenceLength = 128
    private let embeddingWidth = 2304
    private let sigmaData: Float = 0.5
    private let textToImageInstruction =
        "Represent every requested object, color, count, spatial relationship, and camera view exactly. User prompt: "

    init(resourcesURL: URL) throws {
        if let error = Self.validationError(at: resourcesURL) {
            throw NSError(
                domain: "SanaImageGenerator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        self.resourcesURL = resourcesURL
    }

    static func validationError(at resourcesURL: URL) -> String? {
        let required = [
            "SanaTextEncoder.mlmodelc",
            "SanaTransformer.mlmodelc",
            "SanaVAEDecoder.mlmodelc",
            "tokenizer/tokenizer.json",
            "tokenizer/tokenizer_config.json"
        ]
        let missing = required.filter {
            !FileManager.default.fileExists(
                atPath: resourcesURL.appendingPathComponent($0).path
            )
        }
        return missing.isEmpty
            ? nil
            : "Sana Core ML model files are missing: \(missing.joined(separator: ", "))"
    }

    func generate(
        prompt: String,
        steps: Int,
        guidance: Float,
        seed: UInt32
    ) async throws -> UIImage {
        let activeTokenizer = try await tokenizerForResources()
        let cancellation = GenerationCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let image = try autoreleasepool {
                        try generateSync(
                            prompt: prompt,
                            steps: steps,
                            guidance: guidance,
                            seed: seed,
                            tokenizer: activeTokenizer,
                            cancellation: cancellation
                        )
                    }
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        } onCancel: { cancellation.cancel() }
    }

    func unload() {
        queue.async { [self] in
            tokenizer = nil
        }
    }

    private func tokenizerForResources() async throws -> any Tokenizer {
        if let tokenizer { return tokenizer }
        let folder = resourcesURL.appendingPathComponent("tokenizer", isDirectory: true)
        let created = try await AutoTokenizer.from(modelFolder: folder)
        tokenizer = created
        return created
    }

    private func generateSync(
        prompt: String,
        steps: Int,
        guidance: Float,
        seed: UInt32,
        tokenizer: any Tokenizer,
        cancellation: GenerationCancellation
    ) throws -> UIImage {
        if cancellation.isCancelled { throw CancellationError() }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        configuration.allowLowPrecisionAccumulationOnGPU = true

        let instruction = textToImageInstruction
        let tokenInputs = try makeTokenInputs(
            prompt: prompt,
            instruction: instruction,
            tokenizer: tokenizer
        )
        let promptInputs: (embeddings: MLMultiArray, mask: MLMultiArray) = try autoreleasepool {
            let model = try loadModel("SanaTextEncoder.mlmodelc", configuration: configuration)
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "input_ids": tokenInputs.ids,
                "attention_mask": tokenInputs.mask
            ]))
            guard let embeddings = output.featureValue(for: "prompt_embeds")?.multiArrayValue else {
                throw SanaError.missingOutput("prompt_embeds")
            }
            return try selectPromptEmbeddings(
                allEmbeddings: embeddings,
                fullMask: tokenInputs.mask
            )
        }

        let stepCount = max(1, min(steps, 2))
        let schedule = makeSchedule(
            stepCount: stepCount
        )
        var random = SplitMixNormal(seed: UInt64(seed))
        var latents = initialLatents(
            random: &random
        )
        var denoised = latents

        try autoreleasepool {
            let model = try loadModel("SanaTransformer.mlmodelc", configuration: configuration)
            for index in 0..<stepCount {
                if cancellation.isCancelled { throw CancellationError() }
                let current = schedule[index]
                let next = schedule[index + 1]
                let scm = sin(current) / (cos(current) + sin(current))
                let scale = sqrt(scm * scm + (1 - scm) * (1 - scm))
                var modelInput = latents
                for offset in modelInput.indices {
                    modelInput[offset] = (modelInput[offset] / sigmaData) * scale
                }

                let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                    "latent": try floatArray(
                        shape: [1, latentChannels, latentSize, latentSize],
                        values: modelInput
                    ),
                    "prompt_embeds": promptInputs.embeddings,
                    "prompt_attention_mask": promptInputs.mask,
                    "timestep": try floatArray(shape: [1], values: [scm]),
                    "guidance": try floatArray(
                        shape: [1],
                        values: [max(0, min(guidance, 20)) * 0.1]
                    )
                ]))
                guard let predictionArray = output.featureValue(for: "noise_prediction")?.multiArrayValue else {
                    throw SanaError.missingOutput("noise_prediction")
                }

                let prediction = copyFloat32(predictionArray)
                var noisePrediction = prediction
                let coefficient = 1 - 2 * scm + 2 * scm * scm
                for offset in noisePrediction.indices {
                    noisePrediction[offset] = (
                        (1 - 2 * scm) * modelInput[offset] + coefficient * prediction[offset]
                    ) / scale * sigmaData
                }

                denoised = latents
                for offset in denoised.indices {
                    denoised[offset] =
                        cos(current) * latents[offset] - sin(current) * noisePrediction[offset]
                }
                latents = denoised
                if next > 0 {
                    for offset in latents.indices {
                        latents[offset] =
                            cos(next) * denoised[offset] + sin(next) * random.nextNormal() * sigmaData
                    }
                }
            }
        }

        if cancellation.isCancelled { throw CancellationError() }
        return try autoreleasepool {
            let model = try loadModel("SanaVAEDecoder.mlmodelc", configuration: configuration)
            let decoderLatent = denoised.map { $0 / sigmaData }
            let input = try floatArray(
                shape: [1, latentChannels, latentSize, latentSize],
                values: decoderLatent
            )
            let output = try model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: ["latent": input])
            )
            guard let image = output.featureValue(for: "image")?.multiArrayValue else {
                throw SanaError.missingOutput("image")
            }
            return try uiImage(from: image)
        }
    }

    private func loadModel(
        _ filename: String,
        configuration: MLModelConfiguration
    ) throws -> MLModel {
        try MLModel(
            contentsOf: resourcesURL.appendingPathComponent(filename, isDirectory: true),
            configuration: configuration
        )
    }

    private func makeTokenInputs(
        prompt: String,
        instruction: String,
        tokenizer: any Tokenizer
    ) throws -> (ids: MLMultiArray, mask: MLMultiArray) {
        var tokens = tokenizer(instruction + prompt, addSpecialTokens: true)
        if tokens.count > textSequenceLength {
            throw RecipeError.invalid("The reconstruction prompt exceeds this model\'s token limit.")
        }
        let validCount = tokens.count
        if tokens.count < textSequenceLength {
            tokens.append(contentsOf: repeatElement(0, count: textSequenceLength - tokens.count))
        }

        let ids = try MLMultiArray(
            shape: [1, NSNumber(value: textSequenceLength)],
            dataType: .int32
        )
        let mask = try MLMultiArray(
            shape: [1, NSNumber(value: textSequenceLength)],
            dataType: .int32
        )
        let idPointer = ids.dataPointer.assumingMemoryBound(to: Int32.self)
        let maskPointer = mask.dataPointer.assumingMemoryBound(to: Int32.self)
        for index in 0..<textSequenceLength {
            idPointer[index] = Int32(tokens[index])
            maskPointer[index] = index < validCount ? 1 : 0
        }
        return (ids, mask)
    }

    private func selectPromptEmbeddings(
        allEmbeddings: MLMultiArray,
        fullMask: MLMultiArray
    ) throws -> (embeddings: MLMultiArray, mask: MLMultiArray) {
        guard allEmbeddings.count == textSequenceLength * embeddingWidth else {
            throw SanaError.invalidShape("prompt_embeds=\(allEmbeddings.shape)")
        }
        let embeddings = try MLMultiArray(
            shape: [1, NSNumber(value: promptSequenceLength), NSNumber(value: embeddingWidth)],
            dataType: .float32
        )
        let mask = try MLMultiArray(
            shape: [1, NSNumber(value: promptSequenceLength)],
            dataType: .float32
        )
        let source = allEmbeddings.dataPointer.assumingMemoryBound(to: Float16.self)
        let destination = embeddings.dataPointer.assumingMemoryBound(to: Float.self)
        let fullMaskPointer = fullMask.dataPointer.assumingMemoryBound(to: Int32.self)
        let maskPointer = mask.dataPointer.assumingMemoryBound(to: Float.self)
        for outputToken in 0..<promptSequenceLength {
            let sourceToken = outputToken == 0
                ? 0
                : (textSequenceLength - promptSequenceLength + outputToken)
            let sourceBase = sourceToken * embeddingWidth
            let destinationBase = outputToken * embeddingWidth
            for channel in 0..<embeddingWidth {
                destination[destinationBase + channel] = Float(source[sourceBase + channel])
            }
            maskPointer[outputToken] = Float(fullMaskPointer[sourceToken])
        }
        return (embeddings, mask)
    }

    private func makeSchedule(
        stepCount: Int
    ) -> [Float] {
        return stepCount == 1 ? [1.5708, 0] : [1.5708, 1.3, 0]
    }

    private func initialLatents(
        random: inout SplitMixNormal
    ) -> [Float] {
        let count = latentChannels * latentSize * latentSize
        return (0..<count).map { _ in random.nextNormal() * sigmaData }
    }

    private func floatArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: shape.map(NSNumber.init(value:)),
            dataType: .float32
        )
        guard array.count == values.count else {
            throw SanaError.invalidShape("\(shape) != \(values.count)")
        }
        let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
        values.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            pointer.update(from: base, count: values.count)
        }
        return array
    }

    private func copyFloat32(_ array: MLMultiArray) -> [Float] {
        let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: pointer, count: array.count))
    }

    private func uiImage(from tensor: MLMultiArray) throws -> UIImage {
        guard tensor.count == 3 * imageSize * imageSize else {
            throw SanaError.invalidShape("image=\(tensor.shape)")
        }
        let source = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        let plane = imageSize * imageSize
        var pixels = [UInt8](repeating: 255, count: plane * 4)
        for pixel in 0..<plane {
            pixels[pixel * 4] = byte(source[pixel])
            pixels[pixel * 4 + 1] = byte(source[plane + pixel])
            pixels[pixel * 4 + 2] = byte(source[plane * 2 + pixel])
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: imageSize,
                height: imageSize,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: imageSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw SanaError.imageEncoding
        }
        return UIImage(cgImage: cgImage)
    }

    private func byte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, Int((value * 0.5 + 0.5) * 255 + 0.5))))
    }

    enum SanaError: LocalizedError {
        case missingOutput(String)
        case invalidShape(String)
        case imageEncoding

        var errorDescription: String? {
            switch self {
            case .missingOutput(let name):
                return "Sana Core ML output is missing: \(name)"
            case .invalidShape(let detail):
                return "Sana Core ML tensor shape is invalid: \(detail)"
            case .imageEncoding:
                return "Sana image tensor conversion failed"
            }
        }
    }
}

nonisolated private struct SplitMixNormal {
    private var state: UInt64
    private var spare: Float?

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextNormal() -> Float {
        if let spare {
            self.spare = nil
            return spare
        }
        let u1 = max(nextUnit(), 1e-7)
        let u2 = nextUnit()
        let radius = sqrt(-2 * log(u1))
        let angle = 2 * Float.pi * u2
        spare = radius * sin(angle)
        return radius * cos(angle)
    }

    private mutating func nextUnit() -> Float {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Float(Double(z >> 11) / Double(1 << 53))
    }
}
