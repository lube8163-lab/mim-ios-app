import Foundation
import ImagePlayground

enum ImagePlaygroundStyleOption: String, CaseIterable, Identifiable {
    case animation
    case illustration
    case sketch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .animation:
            return "Animation"
        case .illustration:
            return "Illustration"
        case .sketch:
            return "Sketch"
        }
    }
}

@available(iOS 18.4, *)
extension ImagePlaygroundStyleOption {
    var imagePlaygroundStyle: ImagePlaygroundStyle {
        switch self {
        case .animation:
            return .animation
        case .illustration:
            return .illustration
        case .sketch:
            return .sketch
        }
    }
}
