import Foundation
import UIKit

struct QwenGeneratedMetadata {
    let caption: String
    let semanticPrompt: String
    let tags: [String]
}

enum QwenVisionLanguageServiceError: LocalizedError {
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode the input image."
        }
    }
}

actor QwenVisionLanguageService {
    static let shared = QwenVisionLanguageService()

    private let bridge = LlamaCppBridge()
    private var openedModelPath: String?
    private var openedMMProjPath: String?

    func generateMetadata(from image: UIImage) async throws -> QwenGeneratedMetadata {
        let files = try await ModelManager.shared.findQwenVLModelFiles()
        try ensureContext(modelPath: files.modelURL.path, mmprojPath: files.mmprojURL.path)

        let imagePath = try writeImageToTemporaryFile(image)
        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }

        let result = try runWithFallbackPromptIfNeeded(imagePath: imagePath)
        let parsed = parseMetadata(from: sanitizeOutput(result.text))
        return parsed
    }

    private func ensureContext(modelPath: String, mmprojPath: String) throws {
        if openedModelPath == modelPath, openedMMProjPath == mmprojPath {
            return
        }

        try bridge.open(modelPath: modelPath, mmprojPath: mmprojPath)
        openedModelPath = modelPath
        openedMMProjPath = mmprojPath
    }

    private func runWithFallbackPromptIfNeeded(imagePath: String) throws -> LlamaCppRunResult {
        do {
            return try bridge.run(prompt: Self.metadataPrompt, imagePath: imagePath)
        } catch let LlamaCppBridgeError.runFailed(code, _) where code == -13 {
            return try bridge.run(prompt: Self.fallbackPrompt, imagePath: imagePath)
        }
    }

    private func writeImageToTemporaryFile(_ image: UIImage) throws -> String {
        let resized = downscaleIfNeeded(image, maxSide: 896)
        guard let data = resized.jpegData(compressionQuality: 0.9) else {
            throw QwenVisionLanguageServiceError.imageEncodingFailed
        }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen_vl_input_\(UUID().uuidString).jpg")
        try data.write(to: path)
        return path.path
    }

    private func downscaleIfNeeded(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > maxSide else { return image }

        let scale = maxSide / longSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func parseMetadata(from text: String) -> QwenGeneratedMetadata {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let caption = lineValue(prefix: "CAPTION:", in: lines)
        let prompt = lineValue(prefix: "PROMPT:", in: lines)
        let tagsLine = lineValue(prefix: "TAGS:", in: lines)

        let parsedTags = tagsLine
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let safeTags = Array(Self.sanitizeTags(parsedTags).prefix(6))
        let safeCaption = sanitizeSentence(caption.isEmpty ? fallbackCaption(from: lines) : caption)
        let safePrompt = sanitizePrompt(prompt, fallbackTags: safeTags, fallbackCaption: safeCaption)

        return QwenGeneratedMetadata(
            caption: safeCaption,
            semanticPrompt: safePrompt,
            tags: safeTags
        )
    }

    private func lineValue(prefix: String, in lines: [String]) -> String {
        guard let line = lines.first(where: { $0.uppercased().hasPrefix(prefix) }) else {
            return ""
        }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackCaption(from lines: [String]) -> String {
        guard let first = lines.first, !first.isEmpty else {
            return "An image is shown."
        }
        return first
    }

    private func sanitizeSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "An image is shown." }
        let safe = Self.removeUnsafeTerms(from: trimmed)
        if safe.hasSuffix(".") {
            return safe
        }
        return safe + "."
    }

    private func sanitizePrompt(_ prompt: String, fallbackTags: [String], fallbackCaption: String) -> String {
        let raw = prompt
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let safeSegments = Self.sanitizeTags(raw)
        if !safeSegments.isEmpty {
            return safeSegments.joined(separator: ", ")
        }
        if !fallbackTags.isEmpty {
            return fallbackTags.joined(separator: ", ")
        }
        return Self.removeUnsafeTerms(from: fallbackCaption.lowercased())
    }

    private func sanitizeOutput(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: "</think>", with: "")
        out = out.replacingOccurrences(of: "<think>", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeUnsafeTerms(from text: String) -> String {
        let parts = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).lowercased() }
        var safe = text

        for token in parts where SemanticExtractionTask.bannedTokens.contains(token) {
            safe = safe.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }

        return safe
            .replacingOccurrences(of: "\\s+,", with: ",", options: .regularExpression)
            .replacingOccurrences(of: ",\\s*,", with: ", ", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    private static func sanitizeTags(_ tags: [String]) -> [String] {
        tags.filter { tag in
            let tokens = tag
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            return !tokens.contains(where: { SemanticExtractionTask.bannedTokens.contains($0) })
        }
    }

    private static let metadataPrompt = """
    Describe the image for a semantic social app.
    Return exactly 3 lines in English and nothing else.
    CAPTION: one short sentence, maximum 18 words.
    PROMPT: comma-separated Stable Diffusion prompt keywords describing subject, composition, lighting, and style.
    TAGS: up to 6 short comma-separated tags.
    Avoid sexual, violent, or unsafe wording.
    """

    private static let fallbackPrompt = """
    Return exactly 3 lines in English and nothing else.
    CAPTION: a short sentence describing the image.
    PROMPT: comma-separated visual keywords for image generation.
    TAGS: up to 6 short tags.
    """
}
