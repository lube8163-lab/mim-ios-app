import Foundation
import ImagePlayground
import UIKit

enum ImagePlaygroundGeneratorError: LocalizedError {
    case unavailable
    case noImageCreated
    case invalidSourceImage

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Image Playground is unavailable on this device."
        case .noImageCreated:
            return "Image Playground did not return an image."
        case .invalidSourceImage:
            return "Failed to read the source image."
        }
    }
}

actor ImagePlaygroundGenerator {
    static let shared = ImagePlaygroundGenerator()

    private let promptComposer = AppleImagePromptComposer()

    @available(iOS 18.4, *)
    func generateImage(
        from prompt: String,
        tags: [String],
        sourceImage: UIImage?,
        styleOption: ImagePlaygroundStyleOption
    ) async throws -> UIImage {
        let payload = promptComposer.sanitizePrompt(
            prompt: prompt,
            tags: tags,
            usesSourceImage: sourceImage != nil
        )
        let creator = try await ImageCreator()
        let style = styleOption.imagePlaygroundStyle
        guard creator.availableStyles.contains(style) else {
            throw ImagePlaygroundGeneratorError.unavailable
        }

        let conceptCandidates = buildConceptCandidates(payload: payload, tags: tags)

        for candidate in conceptCandidates {
            do {
                return try await generateImage(
                    with: candidate,
                    creator: creator,
                    style: style,
                    sourceImage: sourceImage
                )
            } catch let error as ImageCreator.Error where error == .creationFailed {
                continue
            }
        }

        throw ImageCreator.Error.creationFailed
    }

    func generateImageIfAvailable(
        from prompt: String,
        tags: [String],
        sourceImage: UIImage?,
        styleOption: ImagePlaygroundStyleOption
    ) async throws -> UIImage {
        guard #available(iOS 18.4, *) else {
            throw ImagePlaygroundGeneratorError.unavailable
        }
        return try await generateImage(
            from: prompt,
            tags: tags,
            sourceImage: sourceImage,
            styleOption: styleOption
        )
    }

    @available(iOS 18.4, *)
    private func generateImage(
        with concepts: [String],
        creator: ImageCreator,
        style: ImagePlaygroundStyle,
        sourceImage: UIImage?
    ) async throws -> UIImage {
        var playgroundConcepts = concepts.map(ImagePlaygroundConcept.text)
        if let sourceImage {
            guard let cgImage = sourceImage.cgImage else {
                throw ImagePlaygroundGeneratorError.invalidSourceImage
            }
            playgroundConcepts.append(.image(cgImage))
        }

        for try await created in creator.images(for: playgroundConcepts, style: style, limit: 1) {
            return UIImage(cgImage: created.cgImage)
        }

        throw ImagePlaygroundGeneratorError.noImageCreated
    }

    private func buildConceptCandidates(payload: AppleVisionPromptPayload, tags: [String]) -> [[String]] {
        let cleanedPrompt = payload.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [[String]] = []

        let primary = payload.concepts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !primary.isEmpty {
            candidates.append(Array(primary.prefix(3)))
        }

        if !cleanedPrompt.isEmpty {
            candidates.append([cleanedPrompt])
        }

        if !cleanedTags.isEmpty {
            candidates.append(Array(cleanedTags.prefix(3)))
            candidates.append([cleanedTags.prefix(4).joined(separator: ", ")])
        }

        if let firstTag = cleanedTags.first {
            candidates.append([firstTag])
        }

        candidates.append(["simple illustration"])

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.joined(separator: " | ").lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
