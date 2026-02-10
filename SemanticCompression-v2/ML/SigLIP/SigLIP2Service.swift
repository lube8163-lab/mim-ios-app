//
//  SigLIP2Service.swift
//  SemanticCompression-v2
//
//  Fixed: async embed, safe reload, output-key probing
//

import Foundation
import CoreML
import UIKit

final class SigLIP2Service {

    static let shared = SigLIP2Service()
    private init() {}

    // MARK: - State

    private var model: MLModel?
    private var compiledModelURL: URL?   // mlpackage を compile した結果（キャッシュ）
    private var loadedFromModelPath: String?

    /// ロード済みか（モデル実体があるか）
    var isReady: Bool { model != nil }

    // MARK: - Public (compat)

    /// 既存互換：呼び出し側が MainActor でも安全になるよう、
    /// ここは軽い分岐だけにして、実ロードは別経路に逃がせるようにする。
    func loadIfNeeded() throws {
        try load(force: false)
    }

    /// remove → install の後など、状態がズレたら呼ぶ
    func reset() {
        model = nil
        compiledModelURL = nil
        loadedFromModelPath = nil
        #if DEBUG
        print("🧹 SigLIP2Service reset")
        #endif
    }

    /// ModelManager 側が「削除/再インストールした」タイミングで呼べる
    func reloadIfNeeded() throws {
        // インストールされてるはずなのに model が nil のときや
        // 参照パスが変わった可能性がある時に強制 reload できる
        try load(force: true)
    }

    // MARK: - Embed (CGImage / UIImage)

    /// 推奨：重い処理なので async
    func embed(image: CGImage) async throws -> [Float] {
        try load(force: false)

        guard let model else { throw SigLIP2Error.notLoaded }

        // 重い処理をメインスレッドから外す（CoreML prediction + pixel fill）
        return try await Task.detached(priority: .userInitiated) { [model] in
            try self.runInference(model: model, image: image)
        }.value
    }

    /// 便利オーバーロード（UIImageから）
    func embed(image: UIImage) async throws -> [Float] {
        guard let cg = image.cgImage ?? image.cgImageFromCIImage() else {
            throw SigLIP2Error.invalidImage
        }
        return try await embed(image: cg)
    }

    // MARK: - Loading

    private func load(force: Bool) throws {
        if model != nil, !force { return }

        let url = try ModelManager.shared.findSigLIPModelURL()
        let path = url.path

        // 同じパスから既にロード済みなら、force=falseの時は何もしない
        if !force, let loadedFromModelPath, loadedFromModelPath == path, model != nil {
            return
        }

        loadedFromModelPath = path
        #if DEBUG
        print("🧠 Loading SigLIP2 model from:", path)
        #endif

        // mlpackage の場合 compile が必要
        if url.pathExtension == "mlpackage" {
            // 既に compile 済みURLがあれば再利用（軽量化）
            if let compiledModelURL {
                model = try MLModel(contentsOf: compiledModelURL)
            } else {
                let compiled = try MLModel.compileModel(at: url)
                compiledModelURL = compiled
                model = try MLModel(contentsOf: compiled)
            }
        } else {
            model = try MLModel(contentsOf: url)
        }

        #if DEBUG
        print("✅ SigLIP2 model loaded successfully")
        #endif
    }

    // MARK: - Core inference

    private func runInference(model: MLModel, image: CGImage) throws -> [Float] {

        let input = try makeInput(image: image)
        let output = try model.prediction(from: input)

        // まずは featureNames をログ（デバッグに超重要）
        let names = Array(output.featureNames).sorted()
        #if DEBUG
        print("📤 SigLIP2 Output features:", names)
        #endif

        // 1) ありがちな候補名を優先して探す
        let preferred = ["image_embeds", "embedding", "embeddings", "last_hidden_state", "pooled_output"]
        for key in preferred {
            if let arr = output.featureValue(for: key)?.multiArrayValue {
                #if DEBUG
                print("✅ Using output key:", key, "shape:", arr.shape)
                #endif
                return arr.toFloatArray()
            }
        }

        // 2) 上の候補が無ければ、とにかく最初に見つかった multiArrayValue を拾う
        for key in names {
            if let arr = output.featureValue(for: key)?.multiArrayValue {
                #if DEBUG
                print("✅ Using fallback output key:", key, "shape:", arr.shape)
                #endif
                return arr.toFloatArray()
            }
        }

        throw SigLIP2Error.embeddingMissing
    }

    // MARK: - Input builder

    /// SigLIP2は `pixel_values` が必須（君のログから確定）
    private func makeInput(image: CGImage) throws -> MLFeatureProvider {

        // ここはモデルに合わせて固定（今は224想定）
        let width = 224
        let height = 224

        let resized = resizeCGImage(image, width: width, height: height)

        // [1, 3, H, W]
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )

        fillPixelValuesCHW(resized, into: array)

        return try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": array
        ])
    }
}

// MARK: - Errors

enum SigLIP2Error: LocalizedError {
    case notLoaded
    case embeddingMissing
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "SigLIP2 model not loaded"
        case .embeddingMissing:
            return "SigLIP2 output embedding (multiArray) not found"
        case .invalidImage:
            return "Invalid image (no CGImage/CIImage)"
        }
    }
}

// MARK: - Helpers (UIImage -> CGImage for CIImage)

private extension UIImage {
    func cgImageFromCIImage() -> CGImage? {
        guard let ci = self.ciImage else { return nil }
        let ctx = CIContext(options: nil)
        return ctx.createCGImage(ci, from: ci.extent)
    }
}

// MARK: - Helpers (Resize + Pixel Fill)

// 224x224へリサイズ
private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// CHW (channel-first) で [1,3,H,W] に詰める
private func fillPixelValuesCHW(_ image: CGImage, into array: MLMultiArray) {

    let width = image.width
    let height = image.height

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * 4

    let rawData = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
    defer { rawData.deallocate() }

    let context = CGContext(
        data: rawData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // NOTE: いまは 0..1 正規化のみ。もしモデルが mean/std を要求するならここで適用。
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let r = Float(rawData[offset]) / 255.0
            let g = Float(rawData[offset + 1]) / 255.0
            let b = Float(rawData[offset + 2]) / 255.0

            array[[0, 0, y as NSNumber, x as NSNumber]] = NSNumber(value: r)
            array[[0, 1, y as NSNumber, x as NSNumber]] = NSNumber(value: g)
            array[[0, 2, y as NSNumber, x as NSNumber]] = NSNumber(value: b)
        }
    }
}
