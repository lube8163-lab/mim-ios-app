#if canImport(CoreAI) && !targetEnvironment(simulator)
import CoreAILanguageModels
import CoreGraphics
import Foundation
import Tokenizers

/// CPU metadata and tokenizer only. Keeping this does not keep GPU model weights or image buffers.
@available(iOS 27.0, macOS 27.0, *)
public struct VisionSceneResources: Sendable {
    let decoderURL: URL
    let visionURL: URL
    let bundle: LanguageBundle
    let tokenizer: any Tokenizer
    public init(decoderURL: URL, visionURL: URL) async throws {
        self.decoderURL = decoderURL; self.visionURL = visionURL
        bundle = try LanguageBundle(at: decoderURL)
        tokenizer = try await bundle.loadTokenizer()
    }
}

@available(iOS 27.0, macOS 27.0, *)
public struct VisionSceneResponse: Sendable {
    public let text: String
    public let generatedTokenCount: Int
    public let visionEncodeSeconds: Double
    public let firstTokenSeconds: Double
}

/// A single-image session. The app releases it after analysis so diffusion can use the memory.
@available(iOS 27.0, macOS 27.0, *)
public actor VisionSceneModel {
    private var runtime: VLRuntime?
    private var responding = false

    public init(decoderURL: URL, visionURL: URL) async throws {
        runtime = try await VLRuntime(decoderBundleAt: decoderURL, visionModelAt: visionURL,
                                      arch: .lfm2VL450M)
    }

    public init(resources: VisionSceneResources) async throws {
        runtime = try await VLRuntime(decoderBundleAt: resources.decoderURL, visionModelAt: resources.visionURL,
            arch: .lfm2VL450M, preparedBundle: resources.bundle, preparedTokenizer: resources.tokenizer)
    }

    /// Drain the decoder before returning the memory slot to diffusion.
    public func unload() async {
        try? await runtime?.engine.cancel()
        runtime = nil
    }

    public func respond(to instruction: String, image: CGImage, maximumTokens: Int = 350) async throws -> String {
        try await respondDetailed(to: instruction, image: image, maximumTokens: maximumTokens).text
    }

    public func respondDetailed(to instruction: String, image: CGImage, maximumTokens: Int = 350) async throws -> VisionSceneResponse {
        guard let runtime else { throw VisionError.bundleLayout("Image analysis model has been unloaded.") }
        guard !responding else { throw VisionError.bundleLayout("Image analysis is already running.") }
        responding = true
        defer { responding = false }
        try Task.checkCancellation()
        let arch = runtime.arch
        let tokenizer = runtime.tokenizer
        let vision = arch.visionStart + String(repeating: arch.imagePad, count: arch.mergedTokens) + arch.visionEnd
        let prompt = arch.imStart + arch.userRole + arch.roleSeparator + instruction + vision
            + arch.imEnd + arch.roleSeparator + arch.imStart + arch.assistantRole + arch.roleSeparator
        var tokens = tokenizer.encode(text: prompt).map(Int32.init)
        if let bos = tokenizer.bosTokenId.map(Int32.init), tokens.first != bos { tokens.insert(bos, at: 0) }
        guard let pad = tokenizer.convertTokenToId(arch.imagePad) else {
            throw VisionError.bundleLayout("Image token is missing from the tokenizer.")
        }
        var slots: Int32 = 0
        var imageStart: Int?
        for index in tokens.indices where tokens[index] == Int32(pad) {
            guard Int(slots) < arch.mergedTokens else { throw VisionError.bundleLayout("Unexpected image token count.") }
            if imageStart == nil { imageStart = index }
            tokens[index] = arch.vocab + slots
            slots += 1
        }
        guard Int(slots) == arch.mergedTokens, let imageStart,
              tokens.count + maximumTokens <= runtime.maxContextLength else {
            throw VisionError.bundleLayout("The image prompt does not fit the model context.")
        }
        let visionStarted = ProcessInfo.processInfo.systemUptime
        try await runtime.attach(cgImage: image, segmentID: nil)
        let visionSeconds = ProcessInfo.processInfo.systemUptime - visionStarted
        runtime.setImageShift(imageStart: imageStart)
        try Task.checkCancellation()
        try await runtime.engine.reset()
        let end = tokenizer.convertTokenToId(arch.imEnd)
        var generated: [Int] = []
        let decodeStarted = ProcessInfo.processInfo.systemUptime
        var firstTokenSeconds: Double?
        do {
            let stream = try await runtime.engine.generate(with: tokens, samplingConfiguration: .greedy,
                inferenceOptions: InferenceOptions(maxTokens: maximumTokens))
            for try await output in stream {
                try Task.checkCancellation()
                if firstTokenSeconds == nil { firstTokenSeconds = ProcessInfo.processInfo.systemUptime - decodeStarted }
                let token = Int(output.tokenId)
                if token == tokenizer.eosTokenId || token == end { break }
                generated.append(token)
            }
            // Also drain on EOS or an error: the push-based engine owns a background task.
            try await runtime.engine.cancel()
            try Task.checkCancellation()
        } catch {
            try? await runtime.engine.cancel()
            throw error
        }
        return .init(text: tokenizer.decode(tokens: generated), generatedTokenCount: generated.count,
            visionEncodeSeconds: visionSeconds, firstTokenSeconds: firstTokenSeconds ?? 0)
    }
}
#endif
