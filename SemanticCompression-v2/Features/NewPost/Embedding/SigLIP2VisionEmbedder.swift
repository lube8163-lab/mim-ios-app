import CoreML
import UIKit
import Accelerate

/// ⚠️ このクラスは SigLIP2Service からのみ生成される前提
final class SigLIP2VisionEmbedder {

    // MARK: - Properties

    private let model: MLModel
    private let inputSize = 224

    // MARK: - Init（唯一の生成口）

    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }

        self.model = try MLModel(contentsOf: compiledURL, configuration: config)

        #if DEBUG
        print("✅ SigLIP2 model loaded from:", compiledURL.lastPathComponent)
        #endif
    }

    // MARK: - Embedding

    func embed(_ image: UIImage) throws -> [Float] {

        // 1️⃣ Resize
        let resized = image.resized(to: inputSize)

        // 2️⃣ Prepare input tensor [1, 3, 224, 224]
        let input = try MLMultiArray(
            shape: [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)],
            dataType: .float32
        )

        // 3️⃣ UIImage → CHW
        resized.assignToCHW(into: input)

        // 4️⃣ Predict
        let output = try model.prediction(
            from: MLDictionaryFeatureProvider(dictionary: [
                "pixel_values": input
            ])
        )

        guard
            let key = output.featureNames.first,
            let mlArray = output.featureValue(for: key)?.multiArrayValue
        else {
            throw NSError(
                domain: "SigLIP2",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Model output not found"]
            )
        }

        let vector = mlArray.toFloatArray()

        // 5️⃣ L2 normalize
        var sum: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &sum, vDSP_Length(vector.count))
        let norm = sqrt(sum)

        return vector.map { $0 / max(norm, 1e-6) }
    }
}


extension UIImage {

    func resized(to size: Int) -> UIImage {
        let target = CGSize(width: size, height: size)
        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        draw(in: CGRect(origin: .zero, size: target))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out!
    }

    func assignToCHW(into array: MLMultiArray) {
        guard let cg = self.cgImage else { return }

        let width = cg.width
        let height = cg.height
        let pixelCount = width * height

        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)

        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Float(pixels[i])     / 255.0
                let g = Float(pixels[i + 1]) / 255.0
                let b = Float(pixels[i + 2]) / 255.0

                let idx = y * width + x
                array[0 * pixelCount + idx] = NSNumber(value: r)
                array[1 * pixelCount + idx] = NSNumber(value: g)
                array[2 * pixelCount + idx] = NSNumber(value: b)
            }
        }
    }
}

extension MLMultiArray {

    func toFloatArray() -> [Float] {
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(dataPointer))
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}
