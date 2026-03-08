import Foundation

enum ImageUnderstandingModel: String, CaseIterable, Identifiable {
    case siglip2 = "siglip2"
    case qwen35vl = "qwen35vl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .siglip2:
            return "SigLIP2 Vision Encoder"
        case .qwen35vl:
            return "Qwen3.5-VL-0.8B"
        }
    }
}
