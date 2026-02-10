//
//  VisionLanguageCaptioner.swift
//  SemanticCompression-v2
//
//  FM (FoundationModels) を使わず、RegionTag（位置＋タグ）から
//  “人間が読む用の1文キャプション” を決定論的に生成する。
//  - hallucination しない（タグにない物は絶対言わない）
//  - 再現性（同じ入力→同じ出力）
//  - 英語固定
//

import Foundation

enum VisionLanguageCaptionerError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No region tags provided."
        }
    }
}

/// 位置情報付きタグ → 1文キャプション（決定論）
actor VisionLanguageCaptioner {

    static let shared = VisionLanguageCaptioner()

    // 調整用
    private let maxMainObjects = 3          // 画像全体の主役として列挙する最大数
    private let maxSpatialMentions = 2      // 「in the center」等の位置言及の最大数
    private let minRegionsForGlobal = 1     // 何リージョンに出ても主役候補にできる（1なら普通に採用）
    private let preferCenterRegions = true  // 中央を少し優先

    init() {}

    // MARK: - Public

    /// RegionTag（位置＋タグ）から 1文キャプションを生成
    func generateCaption(from regionTags: [RegionTag]) async throws -> String {

        // 入力が空ならフォールバック不能
        guard !regionTags.isEmpty else {
            throw VisionLanguageCaptionerError.emptyInput
        }

        // 1) 正規化＆安定化（region順とタグ順を固定）
        let normalized = normalizeAndSort(regionTags)

        // 2) グローバル頻度（「何リージョンに出たか」）を数える
        let regionPresence = computeRegionPresence(normalized) // tag -> Set(region)
        let globalCounts: [(tag: String, count: Int)] = regionPresence.map { (tag, regions) in
            (tag: tag, count: regions.count)
        }

        // 3) 主役候補を決める（頻度 desc, tag asc の決定論）
        var mainCandidates = globalCounts
            .filter { $0.count >= minRegionsForGlobal }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.tag < $1.tag
            }
            .map { $0.tag }

        if preferCenterRegions {
            // 中央に出るタグをわずかに優先（ただし決定論）
            // 実装：center系リージョンに出たタグを前方へ（相対順は保持）
            let centerRegions = Set(["center", "upper-center", "lower-center", "middle-left", "middle-right"])
            let centerTags = Set(normalized
                .filter { centerRegions.contains($0.region) }
                .flatMap { $0.tags })

            mainCandidates.sort { a, b in
                let ac = centerTags.contains(a)
                let bc = centerTags.contains(b)
                if ac != bc { return ac && !bc }
                return a < b
            }
        }

        let mainObjects = Array(mainCandidates.prefix(maxMainObjects))

        // 主役が取れなかったら、全タグから安定的に拾う
        let allTagsSorted = allUniqueTagsSorted(normalized)
        let fallbackMain = Array(allTagsSorted.prefix(maxMainObjects))
        let main = mainObjects.isEmpty ? fallbackMain : mainObjects

        // 4) 位置言及（spatial）を作る
        //    - 「そのタグが出るリージョンが1つだけ」なら場所を言える（推測が入らない）
        //    - 主役タグから優先して最大 maxSpatialMentions まで
        let spatialMentions = buildSpatialMentions(
            normalized: normalized,
            regionPresence: regionPresence,
            preferredTags: main,
            limit: maxSpatialMentions
        )

        // 5) 1文にまとめる（決定論テンプレ）
        // 例: "A cat, chair, and table appear in the image, with a cat in the center."
        let sentence = buildOneSentenceCaption(mainTags: main, spatialMentions: spatialMentions)

        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// フォールバック：位置情報なしで、単純なタグ配列からキャプション生成
    func generateCaption(fromFlatTags tags: [String]) async throws -> String {
        let cleaned = tags
            .map { normalizeTag($0) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            throw VisionLanguageCaptionerError.emptyInput
        }

        // 安定的に unique + sort
        let uniq = Array(Set(cleaned)).sorted()
        let main = Array(uniq.prefix(maxMainObjects))

        return buildOneSentenceCaption(mainTags: main, spatialMentions: [])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core logic (deterministic)

    private func normalizeAndSort(_ regionTags: [RegionTag]) -> [RegionTag] {
        // region 順を固定
        let order = regionOrder()

        let normalized: [RegionTag] = regionTags.map { rt in
            let cleanTags = rt.tags
                .map { normalizeTag($0) }
                .filter { !$0.isEmpty }
            // タグ順を固定（Setを使わず sort で安定化）
            let uniqSorted = Array(Set(cleanTags)).sorted()
            return RegionTag(region: rt.region, tags: uniqSorted)
        }

        return normalized.sorted { a, b in
            let ia = order[a.region] ?? 999
            let ib = order[b.region] ?? 999
            if ia != ib { return ia < ib }
            return a.region < b.region
        }
    }

    private func computeRegionPresence(_ normalized: [RegionTag]) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for rt in normalized {
            for tag in rt.tags {
                map[tag, default: []].insert(rt.region)
            }
        }
        return map
    }

    private func allUniqueTagsSorted(_ normalized: [RegionTag]) -> [String] {
        var set = Set<String>()
        for rt in normalized {
            for tag in rt.tags { set.insert(tag) }
        }
        return Array(set).sorted()
    }

    private func buildSpatialMentions(
        normalized: [RegionTag],
        regionPresence: [String: Set<String>],
        preferredTags: [String],
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }

        // タグ→唯一リージョンを確定できるものだけ
        // 例: tag が "center" だけに出たなら "cat in the center"
        func uniqueRegion(for tag: String) -> String? {
            guard let regions = regionPresence[tag], regions.count == 1 else { return nil }
            return regions.first
        }

        // 優先タグから拾う → 足りなければ全タグから拾う（決定論）
        var mentions: [String] = []
        var usedTags = Set<String>()

        let candidates = preferredTags + allUniqueTagsSorted(normalized)
        for tag in candidates {
            if mentions.count >= limit { break }
            if usedTags.contains(tag) { continue }
            guard let r = uniqueRegion(for: tag) else { continue }
            guard let phrase = regionPhrase(r) else { continue }

            // "a <tag> in the center" を作る（タグを勝手に変形しない）
            let obj = humanizeTag(tag)
            let articleObj = withIndefiniteArticle(obj)

            mentions.append("\(articleObj) \(phrase)")
            usedTags.insert(tag)
        }

        return mentions
    }

    // 1文構築
    private func buildOneSentenceCaption(mainTags: [String], spatialMentions: [String]) -> String {
        let objects = mainTags.map { humanizeTag($0) }
        let objectPhrase = englishObjectList(objects)

        // 主語は "A/An ..." or "Multiple ..." のシンプルな形に
        let base: String
        if objects.isEmpty {
            base = "An image is shown."
        } else if objects.count == 1 {
            base = "\(withIndefiniteArticle(objects[0])) appears in the image"
        } else {
            // 複数のときは "X, Y, and Z appear..."
            base = "\(objectPhrase) appear in the image"
        }

        if spatialMentions.isEmpty {
            return base + "."
        } else {
            // 位置言及を "with ..." でつなぐ（1文のまま）
            let spatial = englishObjectList(spatialMentions)
            return base + ", with " + spatial + "."
        }
    }

    // MARK: - Text helpers

    private func normalizeTag(_ s: String) -> String {
        // タグは「同一性」が大事なので、意味が変わる加工はしない。
        // ただし "_" や "-" の区切りは読みやすくする（意味は変えない）
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }

    private func humanizeTag(_ tag: String) -> String {
        // normalizeTag 済みを前提に最小限の読みやすさだけ
        return tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withIndefiniteArticle(_ noun: String) -> String {
        // 雑だけど決定論で十分（hallucinationしない範囲）
        let n = noun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = n.first else { return "a \(noun)" }
        let vowels = Set(["a","e","i","o","u"])
        if vowels.contains(String(first)) {
            return "an \(n)"
        } else {
            return "a \(n)"
        }
    }

    private func englishObjectList(_ items: [String]) -> String {
        let xs = items.filter { !$0.isEmpty }
        if xs.isEmpty { return "" }
        if xs.count == 1 { return xs[0] }
        if xs.count == 2 { return "\(xs[0]) and \(xs[1])" }
        // Oxford comma
        let head = xs.dropLast().joined(separator: ", ")
        return "\(head), and \(xs.last!)"
    }

    // region -> phrase (英語の前置詞句)
    // ここは固定表現なので hallucination ではない
    private func regionPhrase(_ region: String) -> String? {
        switch region {
        case "upper-left":   return "in the upper left"
        case "upper-center": return "in the upper center"
        case "upper-right":  return "in the upper right"
        case "middle-left":  return "on the left"
        case "center":       return "in the center"
        case "middle-right": return "on the right"
        case "lower-left":   return "in the lower left"
        case "lower-center": return "in the lower center"
        case "lower-right":  return "in the lower right"
        default:
            return nil
        }
    }

    private func regionOrder() -> [String: Int] {
        // 安定した順序（読みやすさ重視）
        return [
            "upper-left": 0,
            "upper-center": 1,
            "upper-right": 2,
            "middle-left": 3,
            "center": 4,
            "middle-right": 5,
            "lower-left": 6,
            "lower-center": 7,
            "lower-right": 8
        ]
    }
}
