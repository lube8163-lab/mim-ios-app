import Foundation

enum ImageUnderstandingBackend: String, CaseIterable, Identifiable {
    case automatic
    case siglip2
    case qwen35vl
    case vision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .siglip2:
            return "SigLIP2 Vision Encoder"
        case .qwen35vl:
            return "Qwen3.5-VL-0.8B"
        case .vision:
            return "Apple Vision"
        }
    }
}
