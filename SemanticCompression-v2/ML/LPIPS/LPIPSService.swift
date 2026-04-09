import CoreGraphics
import CoreML
import Foundation
import UIKit

enum LPIPSError: LocalizedError {
    case modelNotFound
    case invalidImage
    case invalidModelOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "LPIPS Core ML model not found"
        case .invalidImage:
            return "Failed to preprocess image for LPIPS evaluation"
        case .invalidModelOutput:
            return "Failed to read LPIPS model output"
        }
    }
}

actor LPIPSService {
    static let shared = LPIPSService()
    static let bundledModelName = "LPIPSAlex"
    static let defaultInputSize = 224

    private var cachedModel: MLModel?

    func evaluateDistance(original: UIImage, generated: UIImage) async throws -> Double {
        let model = try loadModel()
        let source = try Self.makeInputArray(from: original, inputSize: Self.defaultInputSize)
        let target = try Self.makeInputArray(from: generated, inputSize: Self.defaultInputSize)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "source": MLFeatureValue(multiArray: source),
            "target": MLFeatureValue(multiArray: target)
        ])
        let prediction = try await model.prediction(from: provider)
        return Double(try Self.readDistance(from: prediction))
    }

    private func loadModel() throws -> MLModel {
        if let cachedModel {
            return cachedModel
        }

        guard let bundledModel = try Self.findBundledModel() else {
            throw LPIPSError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let modelURL: URL
        switch bundledModel {
        case .compiled(let url):
            modelURL = url
        case .package(let url):
            modelURL = try Self.compileModelIfNeeded(at: url)
        }

        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        cachedModel = model
        return model
    }

    private static func findBundledModel() throws -> BundledModelLocation? {
        if let compiledURL = Bundle.main.url(forResource: bundledModelName, withExtension: "mlmodelc") {
            return .compiled(compiledURL)
        }

        if let packageURL = Bundle.main.url(forResource: bundledModelName, withExtension: "mlpackage") {
            return .package(packageURL)
        }

        guard let resourceRoot = Bundle.main.resourceURL else {
            return nil
        }

        let enumerator = FileManager.default.enumerator(at: resourceRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            let baseName = url.deletingPathExtension().lastPathComponent
            guard baseName == bundledModelName else { continue }
            switch url.pathExtension {
            case "mlmodelc":
                return .compiled(url)
            case "mlpackage":
                return .package(url)
            default:
                continue
            }
        }

        return nil
    }

    private static func compileModelIfNeeded(at sourceURL: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SemanticCompression-v2", isDirectory: true)
            .appendingPathComponent("CompiledModels", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let compiledURL = root.appendingPathComponent("\(bundledModelName).mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return compiledURL
        }

        let temporaryCompiledURL = try MLModel.compileModel(at: sourceURL)
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            try FileManager.default.removeItem(at: compiledURL)
        }
        try FileManager.default.moveItem(at: temporaryCompiledURL, to: compiledURL)
        return compiledURL
    }

    private static func readDistance(from prediction: MLFeatureProvider) throws -> Float {
        if let value = prediction.featureValue(for: "distance") {
            if let scalar = value.multiArrayValue?.flatScalar {
                return scalar
            }
            if value.type == .double {
                return Float(value.doubleValue)
            }
        }

        for featureName in prediction.featureNames {
            guard let value = prediction.featureValue(for: featureName) else {
                continue
            }
            if let scalar = value.multiArrayValue?.flatScalar {
                return scalar
            }
            if value.type == .double {
                return Float(value.doubleValue)
            }
        }

        throw LPIPSError.invalidModelOutput
    }

    private static func makeInputArray(from image: UIImage, inputSize: Int) throws -> MLMultiArray {
        guard let cgImage = image.cgImage else {
            throw LPIPSError.invalidImage
        }

        let rendered = try renderImage(cgImage, inputSize: inputSize)
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)],
            dataType: .float32
        )

        let width = inputSize
        let height = inputSize
        let batchStride = array.strides[0].intValue
        let channelStride = array.strides[1].intValue
        let rowStride = array.strides[2].intValue
        let columnStride = array.strides[3].intValue

        let pixelBuffer = rendered.data
        let floatPointer = array.dataPointer.bindMemory(to: Float32.self, capacity: width * height * 3)

        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = (y * rendered.bytesPerRow) + (x * 4)
                let red = Float32(pixelBuffer[pixelOffset]) / 255.0
                let green = Float32(pixelBuffer[pixelOffset + 1]) / 255.0
                let blue = Float32(pixelBuffer[pixelOffset + 2]) / 255.0
                let values = [(red * 2) - 1, (green * 2) - 1, (blue * 2) - 1]

                for channel in 0..<3 {
                    let index = batchStride + (channel * channelStride) + (y * rowStride) + (x * columnStride)
                    floatPointer[index] = values[channel]
                }
            }
        }

        return array
    }

    private static func renderImage(_ image: CGImage, inputSize: Int) throws -> RenderedImage {
        let squareSize = min(image.width, image.height)
        let cropRect = CGRect(
            x: (image.width - squareSize) / 2,
            y: (image.height - squareSize) / 2,
            width: squareSize,
            height: squareSize
        )

        guard let cropped = image.cropping(to: cropRect) else {
            throw LPIPSError.invalidImage
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = inputSize * 4
        var pixels = [UInt8](repeating: 0, count: inputSize * inputSize * 4)

        guard let context = CGContext(
            data: &pixels,
            width: inputSize,
            height: inputSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LPIPSError.invalidImage
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        return RenderedImage(data: pixels, bytesPerRow: bytesPerRow)
    }
}

private enum BundledModelLocation {
    case compiled(URL)
    case package(URL)
}

private struct RenderedImage {
    let data: [UInt8]
    let bytesPerRow: Int
}

private extension MLMultiArray {
    var flatScalar: Float? {
        guard count > 0 else { return nil }
        switch dataType {
        case .float32:
            return dataPointer.bindMemory(to: Float32.self, capacity: count)[0]
        case .double:
            return Float(dataPointer.bindMemory(to: Double.self, capacity: count)[0])
        case .float16:
            let bits = dataPointer.bindMemory(to: UInt16.self, capacity: count)[0]
            return Float(Float16(bitPattern: bits))
        default:
            return nil
        }
    }
}
