import Foundation
import UIKit

struct QwenGeneratedMetadata {
    let caption: String
    let semanticPrompt: String
    let tags: [String]
}

enum QwenVisionLanguageServiceError: LocalizedError {
    case imageEncodingFailed
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode the input image."
        case .invalidModelOutput:
            return "The model returned invalid metadata output."
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

        return try runWithFallbackPromptIfNeeded(imagePath: imagePath)
    }

    private func ensureContext(modelPath: String, mmprojPath: String) throws {
        if openedModelPath == modelPath, openedMMProjPath == mmprojPath {
            return
        }

        try bridge.open(modelPath: modelPath, mmprojPath: mmprojPath)
        openedModelPath = modelPath
        openedMMProjPath = mmprojPath
    }

    private func resetContext() {
        bridge.close()
        openedModelPath = nil
        openedMMProjPath = nil
    }

    private func runWithFallbackPromptIfNeeded(imagePath: String) throws -> QwenGeneratedMetadata {
        let attempts: [(label: String, prompt: String)] = [
            ("primary", Self.metadataPrompt),
            ("fallback", Self.fallbackPrompt),
            ("rescue", Self.rescuePrompt)
        ]
        let modelPath = openedModelPath
        let mmprojPath = openedMMProjPath
        var sawNoTokenFailure = false

        for (index, attempt) in attempts.enumerated() {
            do {
                let result = try bridge.run(prompt: attempt.prompt, imagePath: imagePath)
                let text = sanitizeOutput(result.text)
                logModelOutput(text, label: attempt.label)
                if let metadata = parseMetadataIfValid(from: text) {
                    return metadata
                }
                if attempt.label == "rescue",
                   let metadata = parseRescueMetadata(from: text) {
                    return metadata
                }
            } catch let LlamaCppBridgeError.runFailed(code, message) where code == -13 {
                sawNoTokenFailure = true
                print("Qwen \(attempt.label) prompt returned no tokens: \(message)")

                if index < attempts.count - 1,
                   let modelPath,
                   let mmprojPath {
                    resetContext()
                    try ensureContext(modelPath: modelPath, mmprojPath: mmprojPath)
                }
                continue
            }
        }

        if sawNoTokenFailure {
            return genericMetadata()
        }

        throw QwenVisionLanguageServiceError.invalidModelOutput
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

        let parsedTags = Self.parseCommaSeparatedItems(tagsLine)
        let safeCaption = sanitizeSentence(caption.isEmpty ? fallbackCaption(from: lines) : caption)
        let safePrompt = sanitizePrompt(prompt, fallbackTags: parsedTags, fallbackCaption: safeCaption)
        let promptTags = Self.parseCommaSeparatedItems(safePrompt)
        let safeTags = Array(Self.sanitizeTags(parsedTags + promptTags).prefix(6))

        return QwenGeneratedMetadata(
            caption: safeCaption,
            semanticPrompt: safePrompt,
            tags: safeTags
        )
    }

    private func parseMetadataIfValid(from text: String) -> QwenGeneratedMetadata? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hasCaption = lines.contains { $0.uppercased().hasPrefix("CAPTION:") }
        let hasPrompt = lines.contains { $0.uppercased().hasPrefix("PROMPT:") }
        let hasTags = lines.contains { $0.uppercased().hasPrefix("TAGS:") }
        guard hasCaption, hasPrompt || hasTags else {
            return nil
        }

        let metadata = parseMetadata(from: text)
        guard !Self.looksLikeInstructionPayload(metadata.caption) else {
            return nil
        }
        guard !Self.looksLikeInstructionPayload(metadata.semanticPrompt) else {
            return nil
        }
        if metadata.caption == "An image is shown.",
           metadata.semanticPrompt == "an image is shown." || metadata.semanticPrompt == "an image is shown" {
            return nil
        }
        if !hasTags, metadata.tags.isEmpty {
            return nil
        }
        if metadata.tags.isEmpty,
           metadata.semanticPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        return metadata
    }

    private func parseRescueMetadata(from text: String) -> QwenGeneratedMetadata? {
        let cleaned = sanitizeSentence(text)
        guard cleaned != "An image is shown." else {
            return nil
        }

        let prompt = Self.removeUnsafeTerms(from: cleaned.lowercased())
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = Array(Self.sanitizeTags(Self.extractTags(from: prompt)).prefix(6))

        return QwenGeneratedMetadata(
            caption: cleaned,
            semanticPrompt: prompt.isEmpty ? "photo, image" : prompt,
            tags: tags.isEmpty ? ["photo", "image"] : tags
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
        let raw = Self.parseCommaSeparatedItems(prompt)

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

    private func logModelOutput(_ text: String, label: String) {
        let flattened = text.replacingOccurrences(of: "\n", with: "\\n")
        print("Qwen \(label) output: \(flattened)")
    }

    private func genericMetadata() -> QwenGeneratedMetadata {
        QwenGeneratedMetadata(
            caption: "An image is shown.",
            semanticPrompt: "photo, image",
            tags: ["photo", "image"]
        )
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
            "short sentence describing the image",
            "brief factual sentence about the visible scene",
            "brief factual sentence",
            "visible scene",
            "short comma-separated tags",
            "visual keywords only",
            "visual keywords separated by commas",
            "simple short tags separated by commas",
            "one sentence describing the visible image"
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
        var seen = Set<String>()
        return tags.filter { tag in
            guard seen.insert(tag).inserted else { return false }
            let tokens = tag
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            return !tokens.contains(where: { SemanticExtractionTask.bannedTokens.contains($0) })
        }
    }

    private static func parseCommaSeparatedItems(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !looksLikeInstructionPayload($0) }
    }

    private static func extractTags(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "and", "or", "of", "on", "in", "with", "to", "for",
            "is", "are", "shows", "showing", "displaying", "placed", "printed",
            "also", "below", "this", "that", "it"
        ]

        return text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { token in
                token.count >= 3 && !stopWords.contains(token)
            }
    }

    private static let metadataPrompt = """
    Reply in English using exactly these 3 lines:
    CAPTION: one sentence describing the visible image
    PROMPT: visual keywords separated by commas
    TAGS: simple nouns separated by commas
    No extra text. No instruction words. No placeholders.
    """

    private static let fallbackPrompt = """
    Respond in English with exactly 3 lines:
    CAPTION: describe only the visible image in one sentence
    PROMPT: visual keywords separated by commas
    TAGS: simple short tags separated by commas
    No extra text. Do not repeat the instruction text. Do not use placeholder wording.
    """

    private static let rescuePrompt = """
    Describe the visible image briefly in English.
    """
}
