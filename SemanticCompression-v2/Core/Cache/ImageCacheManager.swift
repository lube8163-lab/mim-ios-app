//
//  ImageCacheManager.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/08.
//


import UIKit
import CryptoKit

final class ImageCacheManager {

    static let shared = ImageCacheManager()

    private init() {
        createCacheDirectoryIfNeeded()
    }

    // MARK: - Cache directory path
    private let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SemanticCache", isDirectory: true)
    }()

    private func createCacheDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
    }

    // MARK: - File naming rule: SHA256(prompt)
    private func cachePath(for prompt: String) -> URL {
        let hash = SHA256(prompt)
        return folder.appendingPathComponent("\(hash).png")
    }

    // MARK: - Load cached image
    func load(for prompt: String) -> UIImage? {
        let url = cachePath(for: prompt)
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Save & prune
    func save(_ image: UIImage, for prompt: String) {
        let url = cachePath(for: prompt)

        guard let data = image.pngData() else { return }
        try? data.write(to: url)

        pruneCacheIfNeeded()
    }

    // MARK: - LRU prune logic
    private func pruneCacheIfNeeded(maxFiles: Int = 50) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        if files.count <= maxFiles { return }

        // Sort by last modified (oldest first)
        let sorted = files.sorted {
            let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return date1 < date2
        }

        // Delete excess files
        let toDelete = sorted.prefix(files.count - maxFiles)
        toDelete.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

// MARK: - SHA256 helper
private func SHA256(_ text: String) -> String {
    let input = Data(text.utf8)
    let hash = CryptoKit.SHA256.hash(data: input)
    return hash.map { String(format: "%02x", $0) }.joined()
}
