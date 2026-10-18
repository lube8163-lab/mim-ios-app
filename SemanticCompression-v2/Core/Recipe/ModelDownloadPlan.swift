import Foundation

nonisolated struct ModelDownloadFragment: Sendable {
    let url: URL
    let bytes: Int64
}

nonisolated struct ModelDownloadPlan: Sendable {
    let fragments: [ModelDownloadFragment]
    let totalBytes: Int64

    init(fragments: [ModelDownloadFragment]) throws {
        var total: Int64 = 0
        guard !fragments.isEmpty else { throw RecipeError.invalid("モデルの配布ファイルがありません。") }
        for fragment in fragments {
            guard fragment.url.scheme == "https", fragment.bytes > 0,
                  fragment.bytes <= Int64.max - total else { throw RecipeError.invalid("モデルの配布情報が無効です。") }
            total += fragment.bytes
        }
        self.fragments = fragments
        totalBytes = total
    }

    func remaining(at offset: Int64) throws -> [(fragment: ModelDownloadFragment, start: Int64, offset: Int64)] {
        guard (0...totalBytes).contains(offset) else { throw RecipeError.invalid("モデルのdownload位置が無効です。") }
        var start: Int64 = 0
        return fragments.compactMap { fragment in
            defer { start += fragment.bytes }
            guard offset < start + fragment.bytes else { return nil }
            return (fragment, start, max(0, offset - start))
        }
    }
}
