import Foundation

nonisolated enum DiffusionModelShapes {
    static func imageWidth(unet: [Int], decoderInput: [Int], decoderOutput: [Int]) throws -> Int {
        guard unet.count == 4, [1, 2].contains(unet[0]), unet[1] == 4, unet[2] == unet[3],
              [64, 96, 128].contains(unet[3]), decoderInput == [1, 4, unet[2], unet[3]] else {
            throw RecipeError.invalid("UNetとdecoderの入力形状が一致しません。")
        }
        let width = unet[3] * 8
        // Some compiled Core ML models omit their output shape. The renderer also checks
        // the actual image dimensions, so an undeclared output is not a successful render.
        guard decoderOutput.isEmpty || decoderOutput == [1, 3, width, width] else {
            throw RecipeError.invalid("UNetとdecoderの解像度が一致しません。")
        }
        return width
    }
}
