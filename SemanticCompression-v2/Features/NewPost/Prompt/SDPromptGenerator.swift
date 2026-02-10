//
//  SDPromptGenerator.swift
//  SemanticCompression-v2
//
//  Safe SD prompt generator
//  RegionTag → flat keyword list (no spatial words, no sentences)
//

import Foundation

actor SDPromptGenerator {

    static let shared = SDPromptGenerator()
    private init() {}

    /// Generate a safe Stable Diffusion prompt from RegionTag list
    func generatePrompt(from regionTags: [RegionTag]) async throws -> String {

        // 1. Collect all tags
        let allTags = regionTags.flatMap { $0.tags }

        // 2. Normalize + clean
        let cleaned = allTags
            .map { normalize($0) }
            .filter { isValid($0) }

        // 3. Frequency-based ranking
        let ranked = rankByFrequency(cleaned)

        // 4. Pick top-N (safe range)
        let selected = ranked.prefix(8)

        // 5. Fallback
        if selected.isEmpty {
            return "person, indoor room"
        }

        // 6. Final SD prompt (comma-separated keywords)
        return selected.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func normalize(_ tag: String) -> String {
        tag
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValid(_ tag: String) -> Bool {
        // minimal safety: length + no pure punctuation
        guard tag.count >= 2 else { return false }
        guard tag.rangeOfCharacter(from: .letters) != nil else { return false }
        return true
    }

    private func rankByFrequency(_ tags: [String]) -> [String] {
        let counts = Dictionary(grouping: tags, by: { $0 })
            .mapValues { $0.count }

        return counts
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
}
