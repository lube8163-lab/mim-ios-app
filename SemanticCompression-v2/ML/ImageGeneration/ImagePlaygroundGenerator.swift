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

        var concepts = payload.concepts.map(ImagePlaygroundConcept.text)
        if let sourceImage {
            guard let cgImage = sourceImage.cgImage else {
                throw ImagePlaygroundGeneratorError.invalidSourceImage
            }
            concepts.append(.image(cgImage))
        }

        for try await created in creator.images(for: concepts, style: style, limit: 1) {
            return UIImage(cgImage: created.cgImage)
        }

        throw ImagePlaygroundGeneratorError.noImageCreated
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
}
