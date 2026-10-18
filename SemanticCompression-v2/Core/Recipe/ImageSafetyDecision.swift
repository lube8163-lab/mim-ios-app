import Foundation

nonisolated struct ImageSafetyDecision: Sendable {
    static let revision = "swiftformer-s-1d648298-fullframe-v2"
    let nsfw: Double
    let nsfl: Double
    let sfw: Double

    var permitsDisplay: Bool {
        let values = [nsfw, nsfl, sfw]
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              abs(values.reduce(0, +) - 1) < 0.02 else { return false }
        // Treat an unsafe or uncertain majority as blocked. A missing classifier
        // result must never fall through to display or caching.
        return nsfw + nsfl < 0.5 && sfw > 0.5
    }
    static func combining(_ views: [Self]) -> Self? {
        if let blocked = views.first(where: { !$0.permitsDisplay }) { return blocked }
        return views.max { $0.nsfw + $0.nsfl < $1.nsfw + $1.nsfl }
    }
}
