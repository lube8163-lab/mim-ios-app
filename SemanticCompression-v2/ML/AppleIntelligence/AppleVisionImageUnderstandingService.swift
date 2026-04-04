import Foundation
import UIKit
import Vision

enum AppleVisionImageUnderstandingError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to read the selected image."
        }
    }
}

actor AppleVisionImageUnderstandingService {
    static let shared = AppleVisionImageUnderstandingService()

    private let promptComposer = AppleImagePromptComposer()

    func generateMetadata(from image: UIImage) async throws -> QwenGeneratedMetadata {
        guard let cgImage = image.cgImage else {
            throw AppleVisionImageUnderstandingError.invalidImage
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        var bestByLabel: [String: AppleVisionAnalyzedTag] = [:]

        for scope in Self.defaultScopes {
            request.regionOfInterest = scope.regionOfInterest
            try handler.perform([request])

            let results = (request.results as? [VNClassificationObservation] ?? [])
                .filter { $0.confidence >= (scope.isGlobal ? 0.16 : 0.22) }
                .prefix(scope.isGlobal ? 3 : 2)

            for result in results {
                let label = Self.normalizeLabel(result.identifier)
                guard !label.isEmpty else { continue }
                let tag = AppleVisionAnalyzedTag(
                    label: label,
                    confidence: result.confidence,
                    scope: scope.name,
                    location: scope.displayCenter
                )

                if let current = bestByLabel[label], current.confidence >= result.confidence {
                    continue
                }
                bestByLabel[label] = tag
            }
        }

        let analyzedTags = bestByLabel.values.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.label < rhs.label
            }
            return lhs.confidence > rhs.confidence
        }
        let payload = promptComposer.makePayload(tags: analyzedTags, usesSourceImage: true)
        let fallbackTags = Array(payload.tags.prefix(6))
        let caption = Self.makeCaption(from: fallbackTags)

        return QwenGeneratedMetadata(
            caption: caption,
            semanticPrompt: payload.prompt,
            tags: fallbackTags
        )
    }

    private static func makeCaption(from tags: [String]) -> String {
        guard !tags.isEmpty else { return "An image is shown." }
        let text = tags.prefix(3).joined(separator: ", ")
        return "Detected scene: \(text)."
    }

    private static func normalizeLabel(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private struct ScopeInfo {
        let name: String
        let regionOfInterest: CGRect
        let displayCenter: CGPoint
        let isGlobal: Bool
    }

    private static let defaultScopes: [ScopeInfo] = {
        var scopes: [ScopeInfo] = [
            ScopeInfo(
                name: "global",
                regionOfInterest: CGRect(x: 0, y: 0, width: 1, height: 1),
                displayCenter: CGPoint(x: 0.5, y: 0.5),
                isGlobal: true
            )
        ]

        for row in 0..<2 {
            for column in 0..<2 {
                let displayCenter = CGPoint(
                    x: (CGFloat(column) + 0.5) / 2,
                    y: (CGFloat(row) + 0.5) / 2
                )
                scopes.append(
                    ScopeInfo(
                        name: "grid_2x2_r\(row)_c\(column)",
                        regionOfInterest: CGRect(
                            x: CGFloat(column) / 2,
                            y: 1 - CGFloat(row + 1) / 2,
                            width: 0.5,
                            height: 0.5
                        ),
                        displayCenter: displayCenter,
                        isGlobal: false
                    )
                )
            }
        }

        for row in 0..<3 {
            for column in 0..<3 {
                let displayCenter = CGPoint(
                    x: (CGFloat(column) + 0.5) / 3,
                    y: (CGFloat(row) + 0.5) / 3
                )
                scopes.append(
                    ScopeInfo(
                        name: "grid_3x3_r\(row)_c\(column)",
                        regionOfInterest: CGRect(
                            x: CGFloat(column) / 3,
                            y: 1 - CGFloat(row + 1) / 3,
                            width: 1.0 / 3.0,
                            height: 1.0 / 3.0
                        ),
                        displayCenter: displayCenter,
                        isGlobal: false
                    )
                )
            }
        }

        return scopes
    }()
}
