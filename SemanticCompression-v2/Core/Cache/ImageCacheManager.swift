import UIKit
import CryptoKit
import Foundation

@MainActor
final class ImageCacheManager {
    static let shared = ImageCacheManager()
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SemanticCache/generated-safe-v1")
    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let parent = folder.deletingLastPathComponent()
        // Retire the app's evaluation cache; selected originals stay only in the composer.
        for name in ["originals", "scores", "generated"] {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }
    private func url(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".png")
    }
    func load(for key: String) async throws -> UIImage? {
        guard let image = UIImage(contentsOfFile: url(key).path) else { return nil }
        do { try await ImageSafetyService.check(image); return image }
        catch { remove(for: key); throw error }
    }
    func remove(for key: String) { try? FileManager.default.removeItem(at: url(key)) }
    func save(_ image: UIImage, for key: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: url(key), options: .atomic)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in sorted.prefix(max(0, files.count - 50)) { try? FileManager.default.removeItem(at: file) }
    }
    func clearAllCaches() {
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
