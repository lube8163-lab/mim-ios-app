import Foundation
import UIKit
import CoreImage
import Accelerate

enum PrivacyMode: Int, Codable, CaseIterable, Identifiable {
    case l1 = 1
    case l2 = 2
    case l3 = 3
    case l2Prime = 22

    var id: Int { rawValue }

    var titleJA: String {
        switch self {
        case .l1: return "L1"
        case .l2: return "L2"
        case .l3: return "L3"
        case .l2Prime: return "L4"
        }
    }

    var titleEN: String {
        switch self {
        case .l1: return "L1"
        case .l2: return "L2"
        case .l3: return "L3"
        case .l2Prime: return "L4"
        }
    }

    var iconName: String {
        switch self {
        case .l1: return "lock.fill"
        case .l2: return "eye.slash.fill"
        case .l3: return "dial.low.fill"
        case .l2Prime: return "exclamationmark.triangle.fill"
        }
    }

    var storageValue: Int { rawValue }

    static func fromStorageValue(_ value: Int) -> PrivacyMode {
        PrivacyMode(rawValue: value) ?? .l2
    }
}

struct ThumbhashPayload: Codable {
    let thumbhash_b64: String
}

struct DCTPayload: Codable {
    let w: Int
    let h: Int
    let channels: String
    let block: Int
    let quant: String
    let coeffs_b64: String
}

struct LowResPixelsPayload: Codable {
    let w: Int
    let h: Int
    let format: String
    let pixels_b64: String
}

struct L2PrimePayload: Codable {
    let lowres: LowResPixelsPayload
}

enum PostPayload: Codable {
    case thumbhash(ThumbhashPayload)
    case dct(DCTPayload)
    case lowres(L2PrimePayload)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let obj = try c.decode([String: JSONValue].self)

        if case .string(let b64)? = obj["thumbhash_b64"] {
            self = .thumbhash(ThumbhashPayload(thumbhash_b64: b64))
            return
        }

        if let w = obj["w"]?.intValue,
           let h = obj["h"]?.intValue,
           case .string(let ch)? = obj["channels"],
           let block = obj["block"]?.intValue,
           case .string(let quant)? = obj["quant"],
           case .string(let coeffs)? = obj["coeffs_b64"] {
            self = .dct(DCTPayload(
                w: w,
                h: h,
                channels: ch,
                block: block,
                quant: quant,
                coeffs_b64: coeffs
            ))
            return
        }

        if case .object(let lowresObj)? = obj["lowres"],
           let w = lowresObj["w"]?.intValue,
           let h = lowresObj["h"]?.intValue,
           case .string(let format)? = lowresObj["format"],
           case .string(let pixels)? = lowresObj["pixels_b64"] {
            self = .lowres(L2PrimePayload(lowres: LowResPixelsPayload(
                w: w,
                h: h,
                format: format,
                pixels_b64: pixels
            )))
            return
        }

        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported payload shape")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .thumbhash(let p):
            try c.encode(p)
        case .dct(let p):
            try c.encode(p)
        case .lowres(let p):
            try c.encode(p)
        }
    }

    static func fromLegacy(_ lowResGuide: LowResGuide) -> PostPayload? {
        if let jpeg = lowResGuide.jpegBase64, !jpeg.isEmpty {
            return .lowres(L2PrimePayload(lowres: LowResPixelsPayload(
                w: lowResGuide.w,
                h: lowResGuide.h,
                format: "legacy_jpeg_base64",
                pixels_b64: jpeg
            )))
        }

        guard let data = lowResGuide.data else { return nil }
        let flat = data.flatMap { rgb -> [UInt8] in
            [
                UInt8(clamping: rgb.count > 0 ? rgb[0] : 0),
                UInt8(clamping: rgb.count > 1 ? rgb[1] : 0),
                UInt8(clamping: rgb.count > 2 ? rgb[2] : 0),
            ]
        }

        return .lowres(L2PrimePayload(lowres: LowResPixelsPayload(
            w: lowResGuide.w,
            h: lowResGuide.h,
            format: "rgb888",
            pixels_b64: Data(flat).base64EncodedString()
        )))
    }

    static func make(from image: UIImage, mode: PrivacyMode) -> PostPayload? {
        switch mode {
        case .l1:
            return nil
        case .l2:
            guard let b64 = CompactThumbhashCodec.encode(image: image) else { return nil }
            return .thumbhash(ThumbhashPayload(thumbhash_b64: b64))
        case .l3:
            guard let b64 = DCTCodec.encode(image: image) else { return nil }
            return .dct(DCTPayload(
                w: 16,
                h: 16,
                channels: "rgb",
                block: 8,
                quant: "int8",
                coeffs_b64: b64
            ))
        case .l2Prime:
            guard let lowres = LowResRGBCodec.encode(image: image, size: 16) else { return nil }
            return .lowres(L2PrimePayload(lowres: lowres))
        }
    }

    func baseImage() -> UIImage? {
        switch self {
        case .thumbhash(let p):
            return CompactThumbhashCodec.decode(base64: p.thumbhash_b64)
        case .dct(let p):
            return DCTCodec.decode(payload: p)
        case .lowres(let p):
            return LowResRGBCodec.decode(payload: p.lowres)
        }
    }
}

private enum CompactThumbhashCodec {
    // A compact 32-byte "thumbhash-like" payload for low-fidelity color/layout hints.
    static func encode(image: UIImage) -> String? {
        guard let rgb = ImagePixelSampler.rgbPlanes(from: image, size: 8) else { return nil }

        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[0] = 1
        bytes[1] = UInt8(clamping: Int(rgb.r.reduce(0, +) / Float(rgb.r.count)))
        bytes[2] = UInt8(clamping: Int(rgb.g.reduce(0, +) / Float(rgb.g.count)))
        bytes[3] = UInt8(clamping: Int(rgb.b.reduce(0, +) / Float(rgb.b.count)))
        bytes[4] = 8
        bytes[5] = 8

        let grids = [gridAverage(rgb.r), gridAverage(rgb.g), gridAverage(rgb.b)]
        var idx = 6
        for grid in grids {
            for v in grid where idx < 32 {
                bytes[idx] = v
                idx += 1
            }
        }

        while idx < 32 {
            bytes[idx] = bytes[idx % 6]
            idx += 1
        }

        return Data(bytes).base64EncodedString()
    }

    static func decode(base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64), data.count >= 32 else { return nil }
        let bytes = [UInt8](data)

        var planes = (
            r: [UInt8](repeating: bytes[1], count: 32 * 32),
            g: [UInt8](repeating: bytes[2], count: 32 * 32),
            b: [UInt8](repeating: bytes[3], count: 32 * 32)
        )

        let rGrid = Array(bytes[6..<15])
        let gGrid = Array(bytes[15..<24])
        let bGrid = Array(bytes[24..<32]) + [bytes[24]]

        for y in 0..<32 {
            for x in 0..<32 {
                let fx = Float(x) / 31.0 * 2.0
                let fy = Float(y) / 31.0 * 2.0
                let idx = y * 32 + x
                planes.r[idx] = bilinear3x3(grid: rGrid, x: fx, y: fy)
                planes.g[idx] = bilinear3x3(grid: gGrid, x: fx, y: fy)
                planes.b[idx] = bilinear3x3(grid: bGrid, x: fx, y: fy)
            }
        }

        return ImagePixelSampler.imageFromRGB(r: planes.r, g: planes.g, b: planes.b, width: 32, height: 32)
    }

    private static func gridAverage(_ values: [Float]) -> [UInt8] {
        var out: [UInt8] = []
        for gy in 0..<3 {
            for gx in 0..<3 {
                var sum: Float = 0
                var count: Float = 0
                for y in 0..<8 {
                    for x in 0..<8 {
                        let inX = (x >= gx * 3 && x < (gx + 1) * 3) || (gx == 2 && x >= 6)
                        let inY = (y >= gy * 3 && y < (gy + 1) * 3) || (gy == 2 && y >= 6)
                        if inX && inY {
                            sum += values[y * 8 + x]
                            count += 1
                        }
                    }
                }
                out.append(UInt8(clamping: Int((sum / max(1, count)).rounded())))
            }
        }
        return out
    }

    private static func bilinear3x3(grid: [UInt8], x: Float, y: Float) -> UInt8 {
        let x0 = max(0, min(2, Int(floor(x))))
        let y0 = max(0, min(2, Int(floor(y))))
        let x1 = max(0, min(2, x0 + 1))
        let y1 = max(0, min(2, y0 + 1))
        let tx = x - Float(x0)
        let ty = y - Float(y0)

        let p00 = Float(grid[y0 * 3 + x0])
        let p10 = Float(grid[y0 * 3 + x1])
        let p01 = Float(grid[y1 * 3 + x0])
        let p11 = Float(grid[y1 * 3 + x1])

        let a = p00 + (p10 - p00) * tx
        let b = p01 + (p11 - p01) * tx
        let v = a + (b - a) * ty
        return UInt8(clamping: Int(v.rounded()))
    }
}

private enum DCTCodec {
    static func encode(image: UIImage) -> String? {
        guard let rgb = ImagePixelSampler.rgbPlanes(from: image, size: 16) else { return nil }

        let r = dct2D(input: rgb.r, n: 16)
        let g = dct2D(input: rgb.g, n: 16)
        let b = dct2D(input: rgb.b, n: 16)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(192)

        for channel in [r, g, b] {
            for y in 0..<8 {
                for x in 0..<8 {
                    let c = channel[y * 16 + x]
                    let q = Int(round(c / 16.0))
                    let clamped = max(-128, min(127, q))
                    bytes.append(UInt8(bitPattern: Int8(clamped)))
                }
            }
        }

        return Data(bytes).base64EncodedString()
    }

    static func decode(payload: DCTPayload) -> UIImage? {
        guard payload.w == 16,
              payload.h == 16,
              payload.channels == "rgb",
              payload.block == 8,
              payload.quant == "int8",
              let data = Data(base64Encoded: payload.coeffs_b64),
              data.count == 192 else {
            return nil
        }

        let bytes = [UInt8](data)
        let planes: [[Float]] = (0..<3).map { channel in
            var coeff = [Float](repeating: 0, count: 16 * 16)
            let base = channel * 64
            for y in 0..<8 {
                for x in 0..<8 {
                    let raw = Int8(bitPattern: bytes[base + y * 8 + x])
                    coeff[y * 16 + x] = Float(raw) * 16.0
                }
            }
            return idct2D(input: coeff, n: 16)
        }

        let r = planes[0].map { UInt8(clamping: Int($0.rounded())) }
        let g = planes[1].map { UInt8(clamping: Int($0.rounded())) }
        let b = planes[2].map { UInt8(clamping: Int($0.rounded())) }

        return ImagePixelSampler.imageFromRGB(r: r, g: g, b: b, width: 16, height: 16)
    }

    private static func dct2D(input: [Float], n: Int) -> [Float] {
        guard let dct = vDSP.DCT(count: n, transformType: .II) else { return input }

        var rowOut = [Float](repeating: 0, count: n * n)
        var tempIn = [Float](repeating: 0, count: n)
        var tempOut = [Float](repeating: 0, count: n)

        for y in 0..<n {
            for x in 0..<n { tempIn[x] = input[y * n + x] }
            dct.transform(tempIn, result: &tempOut)
            for x in 0..<n { rowOut[y * n + x] = tempOut[x] }
        }

        var out = [Float](repeating: 0, count: n * n)
        for x in 0..<n {
            for y in 0..<n { tempIn[y] = rowOut[y * n + x] }
            dct.transform(tempIn, result: &tempOut)
            for y in 0..<n { out[y * n + x] = tempOut[y] }
        }
        return out
    }

    private static func idct2D(input: [Float], n: Int) -> [Float] {
        guard let idct = vDSP.DCT(count: n, transformType: .III) else { return input }

        var rowOut = [Float](repeating: 0, count: n * n)
        var tempIn = [Float](repeating: 0, count: n)
        var tempOut = [Float](repeating: 0, count: n)

        for y in 0..<n {
            for x in 0..<n { tempIn[x] = input[y * n + x] }
            idct.transform(tempIn, result: &tempOut)
            for x in 0..<n { rowOut[y * n + x] = tempOut[x] }
        }

        var out = [Float](repeating: 0, count: n * n)
        for x in 0..<n {
            for y in 0..<n { tempIn[y] = rowOut[y * n + x] }
            idct.transform(tempIn, result: &tempOut)
            for y in 0..<n { out[y * n + x] = tempOut[y] }
        }
        return out
    }
}

private enum LowResRGBCodec {
    static func encode(image: UIImage, size: Int) -> LowResPixelsPayload? {
        guard let rgb = ImagePixelSampler.rgbBytes(from: image, size: size) else { return nil }
        return LowResPixelsPayload(
            w: size,
            h: size,
            format: "rgb888",
            pixels_b64: Data(rgb).base64EncodedString()
        )
    }

    static func decode(payload: LowResPixelsPayload) -> UIImage? {
        if payload.format == "legacy_jpeg_base64" {
            guard let data = Data(base64Encoded: payload.pixels_b64) else { return nil }
            return UIImage(data: data)
        }

        guard payload.format == "rgb888",
              let data = Data(base64Encoded: payload.pixels_b64) else {
            return nil
        }

        let bytes = [UInt8](data)
        let expected = payload.w * payload.h * 3
        guard bytes.count == expected else { return nil }

        var r = [UInt8](repeating: 0, count: payload.w * payload.h)
        var g = [UInt8](repeating: 0, count: payload.w * payload.h)
        var b = [UInt8](repeating: 0, count: payload.w * payload.h)

        for i in 0..<(payload.w * payload.h) {
            r[i] = bytes[i * 3]
            g[i] = bytes[i * 3 + 1]
            b[i] = bytes[i * 3 + 2]
        }

        return ImagePixelSampler.imageFromRGB(r: r, g: g, b: b, width: payload.w, height: payload.h)
    }
}

private enum ImagePixelSampler {
    static func rgbPlanes(from image: UIImage, size: Int) -> (r: [Float], g: [Float], b: [Float])? {
        guard let bytes = rgbBytes(from: image, size: size) else { return nil }
        var r = [Float](repeating: 0, count: size * size)
        var g = [Float](repeating: 0, count: size * size)
        var b = [Float](repeating: 0, count: size * size)

        for i in 0..<(size * size) {
            r[i] = Float(bytes[i * 3])
            g[i] = Float(bytes[i * 3 + 1])
            b[i] = Float(bytes[i * 3 + 2])
        }

        return (r, g, b)
    }

    static func rgbBytes(from image: UIImage, size: Int) -> [UInt8]? {
        let normalized = image.normalizedOrientation().resizedAspectFill(to: CGSize(width: size, height: size))
        guard let cg = normalized.cgImage else { return nil }

        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &rgba,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var rgb = [UInt8](repeating: 0, count: size * size * 3)
        for i in 0..<(size * size) {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return rgb
    }

    static func imageFromRGB(r: [UInt8], g: [UInt8], b: [UInt8], width: Int, height: Int) -> UIImage? {
        guard r.count == width * height,
              g.count == width * height,
              b.count == width * height else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = r[i]
            pixels[i * 4 + 1] = g[i]
            pixels[i * 4 + 2] = b[i]
            pixels[i * 4 + 3] = 255
        }

        let cf = CFDataCreate(nil, pixels, pixels.count)
        guard let cf,
              let provider = CGDataProvider(data: cf),
              let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cg)
    }
}

struct SDModeProfile {
    let denoiseStrength: Float
    let guidanceScale: Float

    static func forMode(_ mode: PrivacyMode) -> SDModeProfile {
        switch mode {
        case .l1:
            return SDModeProfile(denoiseStrength: 0.95, guidanceScale: 7.0)
        case .l2:
            return SDModeProfile(denoiseStrength: 0.78, guidanceScale: 6.0)
        case .l3:
            return SDModeProfile(denoiseStrength: 0.82, guidanceScale: 6.0)
        case .l2Prime:
            return SDModeProfile(denoiseStrength: 0.80, guidanceScale: 6.0)
        }
    }
}

extension Post {
    var privacyMode: PrivacyMode {
        PrivacyMode(rawValue: mode) ?? .l2
    }

    var effectivePrompt: String? {
        if let p = semanticPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        if !tags.isEmpty {
            return tags.prefix(8).joined(separator: ", ")
        }
        return nil
    }

    func makePreviewImage(targetSize: CGSize = CGSize(width: 32, height: 32)) -> UIImage? {
        let base = baseImageForMode(preview: true)

        guard let base else { return nil }
        return applyPrivacyFilter(base, targetSize: targetSize)
    }

    func makeInitImage(targetSize: CGSize = CGSize(width: 512, height: 512)) -> UIImage? {
        let base = baseImageForMode(preview: false)

        guard let base else { return nil }
        return applyPrivacyFilter(base, targetSize: targetSize)
    }

    private func baseImageForMode(preview: Bool) -> UIImage? {
        switch privacyMode {
        case .l1:
            return Post.makeNoiseBaseImage(size: preview ? CGSize(width: 32, height: 32) : CGSize(width: 64, height: 64))
        case .l2, .l3:
            return payload?.baseImage()
        case .l2Prime:
            return payload?.baseImage() ?? lowResGuide?.makeUIImage()
        }
    }

    private func applyPrivacyFilter(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let resized = image.resizedAspectFill(to: targetSize)
        let blurred = resized.applyingGaussianBlur(radius: 2.4) ?? resized
        let desaturated = blurred.applyingSaturation(0.72) ?? blurred
        return desaturated.addingMicroNoise(intensity: 5)
    }

    private static func makeNoiseBaseImage(size: CGSize) -> UIImage? {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = UInt8.random(in: 96...160)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 255
        }

        let cf = CFDataCreate(nil, pixels, pixels.count)
        guard let cf,
              let provider = CGDataProvider(data: cf),
              let cg = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cg)
    }
}

extension UIImage {
    func applyingSaturation(_ saturation: CGFloat) -> UIImage? {
        guard let input = CIImage(image: self),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        filter.setValue(0.0, forKey: kCIInputBrightnessKey)
        filter.setValue(1.0, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func addingMicroNoise(intensity: UInt8) -> UIImage {
        guard let cg = self.cgImage else { return self }
        let w = cg.width
        let h = cg.height

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        let amount = Int(intensity)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let n = Int.random(in: -amount...amount)
            pixels[i] = UInt8(clamping: Int(pixels[i]) + n)
            pixels[i + 1] = UInt8(clamping: Int(pixels[i + 1]) + n)
            pixels[i + 2] = UInt8(clamping: Int(pixels[i + 2]) + n)
        }

        guard let noised = context.makeImage() else { return self }
        return UIImage(cgImage: noised)
    }
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var intValue: Int? {
        switch self {
        case .number(let v): return Int(v)
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
