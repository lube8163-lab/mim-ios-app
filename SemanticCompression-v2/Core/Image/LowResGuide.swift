import UIKit
import CoreImage

struct LowResGuide: Codable {
    let w: Int
    let h: Int
    let data: [[Int]]?
    let jpegBase64: String?

    static func encode(from image: UIImage, size: Int = 32, jpegQuality: CGFloat = 0.6) -> LowResGuide? {
        let normalized = image.normalizedOrientation()
        let w = size
        let h = size
        let scaled = normalized.resizedAspectFill(to: CGSize(width: w, height: h))
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }
        let b64 = jpeg.base64EncodedString()
        return LowResGuide(w: w, h: h, data: nil, jpegBase64: b64)
    }

    func makeUIImage() -> UIImage? {
        guard w > 0, h > 0 else { return nil }

        if let jpegBase64,
           let decoded = Data(base64Encoded: jpegBase64),
           let img = UIImage(data: decoded) {
            return img
        }

        guard let data, data.count == w * h else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        for (i, rgb) in data.enumerated() {
            guard rgb.count >= 3 else { return nil }
            let idx = i * 4
            pixels[idx] = UInt8(clamping: rgb[0])
            pixels[idx + 1] = UInt8(clamping: rgb[1])
            pixels[idx + 2] = UInt8(clamping: rgb[2])
            pixels[idx + 3] = 255
        }

        let cfdata = CFDataCreate(nil, pixels, pixels.count)
        guard let cfdata else { return nil }
        guard let provider = CGDataProvider(data: cfdata) else { return nil }

        guard let cgimg = CGImage(
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
        ) else { return nil }

        return UIImage(cgImage: cgimg)
    }

    func makePreviewImage(
        targetSize: CGSize = CGSize(width: 256, height: 256),
        blurRadius: CGFloat = 0.6
    ) -> UIImage? {
        guard let base = makeUIImage() else { return nil }
        let scaled = base.resizedAspectFill(to: targetSize)
        if blurRadius <= 0 { return scaled }
        return scaled.applyingGaussianBlur(radius: blurRadius) ?? scaled
    }

    func makeInitImage(
        targetSize: CGSize = CGSize(width: 512, height: 512),
        blurRadius: CGFloat = 0.5
    ) -> UIImage? {
        guard let base = makeUIImage() else { return nil }
        let scaled = base.resizedAspectFill(to: targetSize)
        if blurRadius <= 0 { return scaled }
        return scaled.applyingGaussianBlur(radius: blurRadius) ?? scaled
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedAspectFill(to size: CGSize) -> UIImage {
        let normalized = normalizedOrientation()
        guard let source = normalized.cgImage else {
            return normalized.resized(to: size)
        }

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        let targetAspect = size.width / size.height
        let sourceAspect = sourceWidth / sourceHeight

        let cropRect: CGRect
        if sourceAspect > targetAspect {
            let cropWidth = sourceHeight * targetAspect
            cropRect = CGRect(
                x: (sourceWidth - cropWidth) / 2.0,
                y: 0,
                width: cropWidth,
                height: sourceHeight
            )
        } else {
            let cropHeight = sourceWidth / targetAspect
            cropRect = CGRect(
                x: 0,
                y: (sourceHeight - cropHeight) / 2.0,
                width: sourceWidth,
                height: cropHeight
            )
        }

        let integralCrop = cropRect.integral
        guard let cropped = source.cropping(to: integralCrop) else {
            return normalized.resized(to: size)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }

    func applyingGaussianBlur(radius: CGFloat) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let cropped = output.cropped(to: ciImage.extent)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
