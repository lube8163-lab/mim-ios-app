//
//  SemanticExtractionTask.swift
//  SemanticCompression-v2
//

import Foundation
import UIKit

actor SemanticExtractionTask {

    static let shared = SemanticExtractionTask()
    init() {}

    static let bannedTokens: Set<String> = [
        "seductive", "intimate", "intimacy", "lover", "lust",
        "nude", "naked", "porn", "porno", "sex", "sexual", "erotic", "nsfw",
        "breast", "breasts", "nipple", "nipples", "genital", "genitals",
        "motherfucker", "motherfuckers"
    ]

    // MARK: - Entry point

    func process(
        post: Post,
        taggers: TaggerHolder,
        onTagsExtracted: (([String]) -> Void)? = nil
    ) async {

        guard let image = post.localImage else {
            #if DEBUG
            print("❌ SemanticExtractionTask: No localImage")
            #endif
            return
        }

        await MainActor.run {
            post.status = .processing
        }

        let promptStart = Date()
        let isProModeEnabled = UserDefaults.standard.bool(forKey: AppPreferences.proModeEnabledKey)

        do {
            let backend = ImageUnderstandingModel(
                rawValue: UserDefaults.standard.string(
                    forKey: AppPreferences.selectedImageUnderstandingModelKey
                ) ?? ImageUnderstandingModel.siglip2.rawValue
            ) ?? .siglip2

            switch backend {
            case .siglip2:
                try await Self.processWithSigLIP(
                    post: post,
                    image: image,
                    taggers: taggers,
                    onTagsExtracted: onTagsExtracted
                )
            case .qwen35vl:
                try await Self.processWithQwen(
                    post: post,
                    image: image,
                    onTagsExtracted: onTagsExtracted
                )
            }

            #if DEBUG
            print("✅ Semantic extraction completed for post \(post.id)")
            #endif

            if isProModeEnabled {
                let duration = Date().timeIntervalSince(promptStart)
                let memory = currentMemoryFootprintMB()
                await MainActor.run {
                    post.updatePromptGenerationDiagnostics(duration: duration, memoryMB: memory)
                    let key = regenerationEvaluationCacheKey(
                        postID: post.id,
                        modelID: ModelManager.shared.selectedSDModelID
                    )
                    if let evaluation = post.regenerationEvaluation {
                        ImageCacheManager.shared.saveRegenerationEvaluation(evaluation, for: key)
                    }
                }
            }

        } catch {
            #if DEBUG
            print("❌ SemanticExtractionTask failed:", error)
            #endif

            await MainActor.run {
                post.status = .failed
            }
            await MainActor.run {
                if post.semanticPrompt?.isEmpty ?? true {
                    post.semanticPrompt = "simple scene"
                }
                if post.caption?.isEmpty ?? true {
                    post.caption = ""
                }
                if isProModeEnabled {
                    let duration = Date().timeIntervalSince(promptStart)
                    let memory = currentMemoryFootprintMB()
                    post.updatePromptGenerationDiagnostics(duration: duration, memoryMB: memory)
                    let key = regenerationEvaluationCacheKey(
                        postID: post.id,
                        modelID: ModelManager.shared.selectedSDModelID
                    )
                    if let evaluation = post.regenerationEvaluation {
                        ImageCacheManager.shared.saveRegenerationEvaluation(evaluation, for: key)
                    }
                }
                post.status = .completed
            }
        }
    }

    func syncGeneratedMetadata(post: Post) async throws {
        try await Self.upload(post: post)
    }

    private static func processWithSigLIP(
        post: Post,
        image: UIImage,
        taggers: TaggerHolder,
        onTagsExtracted: (([String]) -> Void)? = nil
    ) async throws {
        let regionTags = try await Self.extractRegionTags(
            from: image,
            tagger: taggers.objectTagger
        )
        let safeRegionTags = Self.sanitizeRegionTags(regionTags)

        let caption: String
        do {
            caption = try await VisionLanguageCaptioner.shared
                .generateCaption(from: safeRegionTags)
        } catch {
            #if DEBUG
            print("⚠️ VisionLanguageCaptioner failed:", error)
            #endif
            caption = ""
        }

        let objectFlatTags = safeRegionTags.flatMap { $0.tags }
        let cleanedObjects = objectFlatTags
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }

        let rankedObjects = Dictionary(grouping: cleanedObjects, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .map { $0.key }

        var streamedTags: [String] = []
        for tag in rankedObjects.prefix(6) {
            streamedTags.append(tag)
            await MainActor.run {
                onTagsExtracted?(streamedTags)
            }
        }

        let objectTop = Array(streamedTags.prefix(6))

        guard let cgImage = image.cgImage else {
            throw NSError(
                domain: "SemanticExtractionTask",
                code: -30,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get CGImage"]
            )
        }

        let globalVec = try await SigLIP2Service.shared.embed(image: cgImage)
        let styleTags = Self.sanitizeTags(
            taggers.styleTagger.tags(from: globalVec, topK: 3)
        )
        let captionTags = Self.sanitizeTags(
            taggers.captionTagger.tags(from: globalVec, topK: 1)
        )
        let finalPrompt = (styleTags + objectTop + captionTags)
            .joined(separator: ", ")

        await MainActor.run {
            post.regionTags = safeRegionTags
            post.caption = caption
            post.semanticPrompt = finalPrompt
            post.tags = objectTop
            post.status = .completed
        }
    }

    private static func processWithQwen(
        post: Post,
        image: UIImage,
        onTagsExtracted: (([String]) -> Void)? = nil
    ) async throws {
        let metadata = try await QwenVisionLanguageService.shared.generateMetadata(from: image)
        let safeTags = Array(Self.sanitizeTags(metadata.tags).prefix(6))

        if !safeTags.isEmpty {
            await MainActor.run {
                onTagsExtracted?(safeTags)
            }
        }

        await MainActor.run {
            post.regionTags = nil
            post.caption = metadata.caption
            post.semanticPrompt = metadata.semanticPrompt
            post.tags = safeTags
            post.status = .completed
        }
    }

    // MARK: - Multi-scale region extraction (metadata)

    private static func extractRegionTags(
        from image: UIImage,
        tagger: EmbeddingTagger
    ) async throws -> [RegionTag] {

        var all: [RegionTag] = []
        let gridSizes = [1, 2]

        for grid in gridSizes {
            let blocks = splitImage(image, grid: grid)

            for b in blocks {

                guard let cgImage = b.crop.cgImage else {
                    throw NSError(
                        domain: "SemanticExtractionTask",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to convert UIImage to CGImage"]
                    )
                }

                let vec = try await SigLIP2Service.shared.embed(image: cgImage)
                let tags = tagger.tags(from: vec, topK: 4)

                let region = (grid == 1)
                    ? "global"
                    : regionName(grid: grid, gx: b.gx, gy: b.gy)

                all.append(RegionTag(region: region, tags: tags))
            }
        }

        return mergeByRegionKeepingDuplicates(all)
    }

    // MARK: - Image splitting

    private struct Block {
        let crop: UIImage
        let gx: Int
        let gy: Int
    }

    private static func splitImage(_ img: UIImage, grid: Int) -> [Block] {
        guard let cg = img.cgImage else { return [] }

        let w = cg.width / grid
        let h = cg.height / grid

        var out: [Block] = []

        for gy in 0..<grid {
            for gx in 0..<grid {
                let rect = CGRect(x: gx * w, y: gy * h, width: w, height: h)
                if let crop = cg.cropping(to: rect) {
                    out.append(
                        Block(
                            crop: UIImage(cgImage: crop),
                            gx: gx,
                            gy: gy
                        )
                    )
                }
            }
        }
        return out
    }

    // MARK: - Region naming

    private static func regionName(grid: Int, gx: Int, gy: Int) -> String {
        return "g\(grid)-r\(gy)-c\(gx)"
    }

    // MARK: - Merge tags of same region (KEEP duplicates)

    private static func mergeByRegionKeepingDuplicates(_ list: [RegionTag]) -> [RegionTag] {
        let grouped = Dictionary(grouping: list, by: { $0.region })

        let keys = grouped.keys.sorted { a, b in
            if a == "global" { return true }
            if b == "global" { return false }
            return a < b
        }

        return keys.map { region in
            let arr = grouped[region] ?? []
            let tags = arr.flatMap { $0.tags }
            return RegionTag(region: region, tags: tags)
        }
    }

    // MARK: - SD fallback

    private static func fallbackSDPrompt(from flatTags: [String]) -> String {
        let lower = flatTags.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("person") || $0.contains("human") || $0.contains("man") || $0.contains("woman") || $0.contains("athlete") }) {
            return "person, simple scene"
        }
        if lower.contains(where: { $0.contains("mountain") || $0.contains("snow") || $0.contains("sky") || $0.contains("outdoor") }) {
            return "outdoor scene, mountain, sky"
        }
        if lower.contains(where: { $0.contains("room") || $0.contains("bed") || $0.contains("indoor") }) {
            return "indoor room, simple scene"
        }
        return "simple scene"
    }

    private static func sanitizeTags(_ tags: [String]) -> [String] {
        tags.filter { isSafeTag($0) }
    }

    private static func sanitizeRegionTags(_ regionTags: [RegionTag]) -> [RegionTag] {
        regionTags.compactMap { regionTag in
            let safe = sanitizeTags(regionTag.tags)
            if safe.isEmpty { return nil }
            return RegionTag(region: regionTag.region, tags: safe)
        }
    }

    private static func isSafeTag(_ tag: String) -> Bool {
        let tokens = tag
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for token in tokens {
            if bannedTokens.contains(token) {
                return false
            }
        }
        return true
    }

    // MARK: - Upload to server

    private static func upload(post: Post) async throws {
        let url = URL(
            string: "https://semantic-feed.semantic-compression.workers.dev/updatePost"
        )!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "id": post.id,
            "caption": post.caption ?? NSNull(),
            "semanticPrompt": post.semanticPrompt ?? NSNull(),
            "tags": post.tags
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("✅ Updated semanticPrompt for:", post.id)
        #endif
    }
}
