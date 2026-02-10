//
//  ImageCache.swift
//  SemanticCompressionApp
//

import UIKit

final class ImageCache {
    static let shared = ImageCache()

    // id(Post.id) → UIImage
    private var storage: [String: UIImage] = [:]
    private let maxCount = 100

    private init() {}

    func image(for id: String) -> UIImage? {
        return storage[id]
    }

    func store(_ image: UIImage, for id: String) {
        storage[id] = image

        // 多すぎたら古い順に減らす（とても雑な実装でOKのやつ）
        if storage.count > maxCount {
            let overflow = storage.count - maxCount
            let keys = Array(storage.keys.prefix(overflow))
            keys.forEach { storage.removeValue(forKey: $0) }
        }
    }
}
