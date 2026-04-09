//
//  ImageCacheManager.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/08.
//


import UIKit
import CryptoKit
import Foundation

final class ImageCacheManager {

    static let generatedImageMaxFiles = 50
    static let proModeOriginalMaxFiles = 50
    static let defaultProModeCacheLimitMB = 200

    enum CacheNamespace: String {
        case generatedImages = "generated"
        case originalImages = "originals"
        case semanticScores = "scores"
    }

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
        for namespace in [CacheNamespace.generatedImages, .originalImages, .semanticScores] {
            try? FileManager.default.createDirectory(
                at: folder(for: namespace),
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - File naming rule: SHA256(prompt)
    private func folder(for namespace: CacheNamespace) -> URL {
        folder.appendingPathComponent(namespace.rawValue, isDirectory: true)
    }

    private func imageCachePath(for key: String, namespace: CacheNamespace) -> URL {
        let hash = SHA256(key)
        return folder(for: namespace).appendingPathComponent("\(hash).png")
    }

    private func scoreCachePath(for key: String) -> URL {
        let hash = SHA256(key)
        return folder(for: .semanticScores).appendingPathComponent("\(hash).txt")
    }

    private func evaluationCachePath(for key: String) -> URL {
        let hash = SHA256(key)
        return folder(for: .semanticScores).appendingPathComponent("\(hash).json")
    }

    // MARK: - Load cached image
    func load(for prompt: String, namespace: CacheNamespace = .generatedImages) -> UIImage? {
        let url = imageCachePath(for: prompt, namespace: namespace)
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Save & prune
    func save(_ image: UIImage, for prompt: String, namespace: CacheNamespace = .generatedImages) {
        let url = imageCachePath(for: prompt, namespace: namespace)

        guard let data = image.pngData() else { return }
        try? data.write(to: url)

        switch namespace {
        case .generatedImages:
            pruneCacheIfNeeded(namespace: namespace, maxFiles: Self.generatedImageMaxFiles)
        case .originalImages:
            pruneCacheIfNeeded(namespace: namespace, maxFiles: Self.proModeOriginalMaxFiles)
            pruneCacheSizeIfNeeded(namespace: namespace, maxBytes: proModeCacheLimitBytes)
        case .semanticScores:
            break
        }
    }

    func remove(for prompt: String, namespace: CacheNamespace = .generatedImages) {
        let url = imageCachePath(for: prompt, namespace: namespace)
        try? FileManager.default.removeItem(at: url)
    }

    func loadSemanticScore(for key: String) -> Double? {
        if let evaluation = loadRegenerationEvaluation(for: key), let score = evaluation.semanticScore {
            return score
        }

        let url = scoreCachePath(for: key)
        guard
            let data = try? Data(contentsOf: url),
            let string = String(data: data, encoding: .utf8),
            let score = Double(string)
        else {
            return nil
        }
        return score
    }

    func saveSemanticScore(_ score: Double, for key: String) {
        let url = scoreCachePath(for: key)
        let clamped = max(0, min(score, 1))
        let text = String(clamped)
        guard let data = text.data(using: .utf8) else { return }
        try? data.write(to: url)
    }

    func loadRegenerationEvaluation(for key: String) -> RegenerationEvaluation? {
        let url = evaluationCachePath(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RegenerationEvaluation.self, from: data)
    }

    func saveRegenerationEvaluation(_ evaluation: RegenerationEvaluation, for key: String) {
        let url = evaluationCachePath(for: key)
        guard let data = try? JSONEncoder().encode(evaluation) else { return }
        try? data.write(to: url)

        if let score = evaluation.score {
            saveSemanticScore(score, for: key)
        }
    }

    func removeSemanticScore(for key: String) {
        let url = scoreCachePath(for: key)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: evaluationCachePath(for: key))
    }

    func clearAllGeneratedImages() {
        clear(namespace: .generatedImages)
    }

    func clearAllOriginalImages() {
        clear(namespace: .originalImages)
    }

    func clearAllSemanticScores() {
        clear(namespace: .semanticScores)
    }

    func clearAllCaches() {
        clearAllGeneratedImages()
        clearAllOriginalImages()
        clearAllSemanticScores()
    }

    func totalCacheUsageBytes(in namespaces: [CacheNamespace]) -> Int64 {
        namespaces.reduce(0) { $0 + cacheUsageBytes(in: $1) }
    }

    func cacheUsageBytes(in namespace: CacheNamespace) -> Int64 {
        let target = folder(for: namespace)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        return files.reduce(into: Int64(0)) { total, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    func enforceCachePolicies() {
        pruneCacheIfNeeded(namespace: .generatedImages, maxFiles: Self.generatedImageMaxFiles)
        pruneCacheIfNeeded(namespace: .originalImages, maxFiles: Self.proModeOriginalMaxFiles)
        pruneCacheSizeIfNeeded(namespace: .originalImages, maxBytes: proModeCacheLimitBytes)
    }

    // MARK: - LRU prune logic
    private func clear(namespace: CacheNamespace) {
        let target = folder(for: namespace)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func pruneCacheIfNeeded(namespace: CacheNamespace, maxFiles: Int) {
        let target = folder(for: namespace)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: target,
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

    private var proModeCacheLimitBytes: Int64 {
        let configuredMB = UserDefaults.standard.integer(forKey: AppPreferences.proModeCacheLimitMBKey)
        let normalizedMB = configuredMB > 0 ? configuredMB : Self.defaultProModeCacheLimitMB
        return Int64(normalizedMB) * 1024 * 1024
    }

    private func pruneCacheSizeIfNeeded(namespace: CacheNamespace, maxBytes: Int64) {
        guard maxBytes > 0 else { return }

        let target = folder(for: namespace)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        var entries = files.map { url -> (url: URL, date: Date, size: Int64) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            let date = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            return (url, date, size)
        }
        .sorted { $0.date < $1.date }

        var totalBytes = entries.reduce(Int64(0)) { $0 + $1.size }
        guard totalBytes > maxBytes else { return }

        while totalBytes > maxBytes, let victim = entries.first {
            totalBytes -= victim.size
            try? FileManager.default.removeItem(at: victim.url)
            entries.removeFirst()
        }
    }
}

// MARK: - SHA256 helper
private func SHA256(_ text: String) -> String {
    let input = Data(text.utf8)
    let hash = CryptoKit.SHA256.hash(data: input)
    return hash.map { String(format: "%02x", $0) }.joined()
}
