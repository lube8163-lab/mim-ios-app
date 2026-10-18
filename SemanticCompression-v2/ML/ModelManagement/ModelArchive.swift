import Foundation
import ZIPFoundation

nonisolated enum ModelArchive {
    static func install(archiveAt archiveURL: URL, root: URL, family: PipelineFamily) throws {
        try install(archiveAt: archiveURL, root: root, skipCRC32: family == .flux2Klein4B) { staging in
            if family == .flux2Klein4B {
                try CoreAIFluxAssets.validate(at: staging, verifyHashes: true)
                try addBundledNotices(to: staging)
                return
            }
            guard ModelAssets.requiredFilesExist(at: staging, family: family) else {
                throw RecipeError.invalid("モデル資産が不足しています。tokenizer・text encoder・UNet・decoderを確認してください。")
            }
        }
    }

    static func installCoreAIVision(archiveAt archiveURL: URL, root: URL) throws {
        try install(archiveAt: archiveURL, root: root) {
            try CoreAIVisionAssets.validate(at: $0, verifyHashes: true)
            try addBundledNotices(to: $0)
        }
    }

    private static func addBundledNotices(to root: URL) throws {
        guard let source = Bundle.main.url(forResource: "ModelLicenseNotices", withExtension: "txt") else {
            throw RecipeError.invalid("ライセンス本文を読み込めません。")
        }
        // Add a separate notice; retain every upstream LICENSE/NOTICE and pinned model byte.
        try Data(contentsOf: source).write(to: root.appendingPathComponent("MIM_MODEL_NOTICES.txt"), options: .atomic)
    }

    private static func install(archiveAt archiveURL: URL, root: URL, skipCRC32: Bool = false, validate: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let parent = root.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".model-install-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".model-previous-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let entries = Array(archive).filter { !$0.path.hasPrefix("__MACOSX/") }
        let topNames = Set(entries.compactMap { $0.path.split(separator: "/").first.map(String.init) })
        let stripTop = topNames.count == 1 && !(topNames.first?.hasSuffix(".mlmodelc") ?? true)
        for entry in entries {
            try Task.checkCancellation()
            let components = entry.path.split(separator: "/")
            guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"), !components.contains(".."),
                  entry.type != .symlink else { throw RecipeError.invalid("モデルarchiveのファイル形式が無効です。") }
            let relative = (stripTop ? components.dropFirst() : components[...]).joined(separator: "/")
            guard !relative.isEmpty else { continue }
            let destination = staging.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // FLUX checks both the archive SHA-256 and every installed file hash.
            _ = try autoreleasepool { try archive.extract(entry, to: destination, skipCRC32: skipCRC32) }
        }
        try validate(staging)
        try Data().write(to: staging.appendingPathComponent(".installed"))
        try Task.checkCancellation()
        try fm.moveItem(at: root, to: backup)
        do { try fm.moveItem(at: staging, to: root) }
        catch { try? fm.moveItem(at: backup, to: root); throw error }
        try? fm.removeItem(at: backup)
    }
}
