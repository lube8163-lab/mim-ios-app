import UIKit
import Vision
import CoreML
import ImageIO

actor ImageSafetyRuntime {
    static let shared = ImageSafetyRuntime()
    private var model: VNCoreMLModel?

    func assess(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> ImageSafetyDecision {
        try Task.checkCancellation()
        if model == nil {
            guard let url = Bundle.main.url(forResource: "ImageSafetyClassifier", withExtension: "mlmodelc") else {
                throw RecipeError.unsupported("画像の安全性を確認するモデルがありません。")
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: configuration))
        }
        guard let model else { throw RecipeError.invalid("画像の安全性を確認できませんでした。") }
        return try autoreleasepool {
            let wholeFrame = VNCoreMLRequest(model: model)
            wholeFrame.imageCropAndScaleOption = .scaleFit
            var requests = [wholeFrame]
            if image.width != image.height {
                let center = VNCoreMLRequest(model: model)
                center.imageCropAndScaleOption = .centerCrop
                requests.append(center)
            }
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform(requests)
            try Task.checkCancellation()
            let views: [ImageSafetyDecision] = try requests.map { request in
                guard let results = request.results as? [VNClassificationObservation],
                      let nsfw = results.first(where: { $0.identifier == "NSFW" }),
                      let nsfl = results.first(where: { $0.identifier == "NSFL" }),
                      let sfw = results.first(where: { $0.identifier == "SFW" }) else {
                    throw RecipeError.invalid("画像の安全性を確認できませんでした。")
                }
                return .init(nsfw: Double(nsfw.confidence), nsfl: Double(nsfl.confidence), sfw: Double(sfw.confidence))
            }
            guard let decision = ImageSafetyDecision.combining(views) else {
                throw RecipeError.invalid("画像の安全性を確認できませんでした。")
            }
            return decision
        }
    }
}

@MainActor
enum ImageSafetyService {
    @discardableResult
    static func check(_ image: UIImage) async throws -> ImageSafetyDecision {
        guard let cgImage = image.cgImage else { throw RecipeError.invalid("画像の安全性を確認できませんでした。") }
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: throw RecipeError.invalid("画像の向きを確認できませんでした。")
        }
        let result = try await ImageSafetyRuntime.shared.assess(cgImage, orientation: orientation)
        guard result.permitsDisplay else {
            throw RecipeError.invalid("安全性の確認により、この画像は再生成・表示できません。")
        }
        return result
    }
}
