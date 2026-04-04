import Foundation

enum ImageGenerationBackend: String, CaseIterable, Identifiable {
    case automatic
    case stableDiffusion
    case imagePlayground

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .stableDiffusion:
            return "Stable Diffusion"
        case .imagePlayground:
            return "Image Playground"
        }
    }

    var cacheKeyPrefix: String {
        switch self {
        case .automatic:
            return rawValue
        case .stableDiffusion:
            return "sd"
        case .imagePlayground:
            return "imageplayground"
        }
    }
}
