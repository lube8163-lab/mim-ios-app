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
        guard let first = lines.first(where: { !Self.looksLikeInstructionLine($0) }), !first.isEmpty else {
            return "An image is shown."
        }
        return first
    }

    private func sanitizeSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "An image is shown." }
        if Self.looksLikeInstructionPayload(trimmed) {
            return "An image is shown."
        }
        let safe = Self.removeUnsafeTerms(from: trimmed)
        guard !safe.isEmpty else { return "An image is shown." }
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

        let safeSegments = Self.sanitizeTags(raw).filter { !Self.looksLikeInstructionPayload($0) }
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

    private static func looksLikeInstructionLine(_ line: String) -> Bool {
        looksLikeInstructionPayload(
            line
                .replacingOccurrences(of: "CAPTION:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "PROMPT:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "TAGS:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func looksLikeInstructionPayload(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let instructionFragments = [
            "one short sentence",
            "maximum 18 words",
            "comma-separated",
            "stable diffusion prompt keywords",
            "describing subject",
            "return exactly 3 lines",
            "nothing else",
            "up to 6 short",
            "avoid sexual",
            "prompt keywords",
            "short sentence describing the image"
        ]
        return instructionFragments.contains(where: { normalized.contains($0) })
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
    Analyze the image and reply in English using exactly this format:
    CAPTION: [brief factual sentence about the visible scene]
    PROMPT: [comma-separated visual keywords only]
    TAGS: [up to 6 short comma-separated tags]

    Rules:
    - Do not repeat these instructions.
    - Do not include brackets, notes, or explanations.
    - CAPTION must describe the actual image content.
    - PROMPT must contain only visual keywords such as subject, color, angle, lighting, material, and background.
    - TAGS must be simple nouns or short noun phrases.
    - Avoid sexual, violent, or unsafe wording.
    """

    private static let fallbackPrompt = """
    Respond in English with exactly 3 lines:
    CAPTION: brief factual sentence
    PROMPT: comma-separated visual keywords only
    TAGS: up to 6 short tags
    Do not repeat the instruction text.
    """
}
