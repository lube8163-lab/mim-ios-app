import Foundation

/// Keeps the visible subjects together before spending the encoder's remaining
/// token budget on background and lighting. The caller supplies the real tokenizer.
nonisolated enum ScenePromptBuilder {
    static let sdNegativePrompt = "deformed, distorted, malformed, fused objects, extra limbs, bad anatomy, blurry, low quality, nudity, explicit sexual content, graphic gore"

    static func flux(prompt: String, counts: String, arrangement: String, relationships: String,
                     colors: String, background: String, lighting: String, medium: String) throws -> String {
        let facts = [("Count", counts), ("Placement", arrangement), ("Relations", relationships),
                     ("Colors", colors), ("Background", background), ("Lighting", lighting), ("Medium", medium)]
        let result = ([prompt] + facts.filter {
            let value = $0.1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !value.isEmpty && !["unknown", "none", "unclear", "n/a"].contains(value)
        }.map { "\($0.0): \($0.1)." }).joined(separator: " ")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.count <= 2000 else {
            throw RecipeError.invalid("写真の説明が長すぎます。より単純な構図で再試行してください。")
        }
        return result
    }

    static func build(prompt: String, subjects: [String], counts: String, arrangement: String,
                      relationships: String, colors: String, background: String, lighting: String,
                      medium: String, maximumTokens: Int, tokenCount: (String) -> Int) throws -> String {
        let normalizedPrompt = explicitSubjects(prompt, subjects: subjects, counts: counts, arrangement: arrangement)
        let clauses = normalizedPrompt.components(separatedBy: CharacterSet(charactersIn: ",.;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clauses.isEmpty, maximumTokens > 2 else { throw RecipeError.invalid("写真の説明が不足しています。") }
        let subjectNouns = Set(subjects.compactMap { words($0).last })
        let essentialIndices = clauses.indices.filter { $0 == 0 || !Set(words(clauses[$0])).isDisjoint(with: subjectNouns) }
        var selected = essentialIndices.map { clauses[$0] }
        func assembled() -> String { selected.joined(separator: ", ") }
        guard tokenCount(assembled()) <= maximumTokens else {
            throw RecipeError.invalid("写真の主題が多すぎます。より単純な構図の写真で再試行してください。")
        }
        // Counts and placement outrank secondary details; never cut a subject's
        // phrase in the middle or silently truncate the encoder input.
        let placement = subjects.count == 1 ? (arrangement.components(separatedBy: ":").last ?? arrangement)
            : (arrangement.contains(":") ? "" : arrangement)
        let optional = [placement] + clauses.indices
            .filter { !essentialIndices.contains($0) }.map { clauses[$0] } + [background, lighting]
        for detail in optional {
            let cleaned = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = words(cleaned)
            guard !normalized.isEmpty, !["unknown", "none", "unclear", "na"].contains(cleaned.lowercased()),
                  !Set(normalized).isSubset(of: Set(words(assembled()))) else { continue }
            selected.append(cleaned)
            if tokenCount(assembled()) > maximumTokens { selected.removeLast() }
        }
        return assembled()
    }

    private static func explicitSubjects(_ prompt: String, subjects: [String], counts: String, arrangement: String) -> String {
        func value(_ field: String, for subject: String) -> String? {
            let noun = words(subject).last
            for item in field.components(separatedBy: ";") {
                let pair = item.components(separatedBy: ":")
                if pair.count == 2, words(pair[0]).last == noun { return pair[1].trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            return subjects.count == 1 && !field.contains(":") ? field : nil
        }
        let countWords = [1: "one", 2: "two", 3: "three", 4: "four", 5: "five"]
        func number(_ subject: String) -> Int? {
            guard let raw = value(counts, for: subject), let parsed = words(raw).first,
                  let n = Int(parsed), (1...100).contains(n) else { return nil }
            return n
        }
        let missing = subjects.filter { subject in
            guard let noun = words(subject).last else { return false }
            return !words(prompt).contains(noun)
        }
        if !missing.isEmpty {
            let essentials = missing.map { subject in
                var text = (number(subject).map { (countWords[$0] ?? String($0)) + " " } ?? "") + subject
                if let position = value(arrangement, for: subject), ["left", "right", "center", "centered", "middle"].contains(position.lowercased()) {
                    text += position == "centered" ? ", centered" : " on the " + position
                }
                return text
            }.joined(separator: " and ")
            // Generic summaries such as "two shapes" are replaced by the named
            // subjects, rather than asking the diffusion model for both groups.
            let clauses = prompt.components(separatedBy: CharacterSet(charactersIn: ",.;\n"))
            let remainder = missing.count == subjects.count ? clauses.dropFirst().joined(separator: ", ") : prompt
            return essentials + (remainder.isEmpty ? "" : ", " + remainder)
        }
        var result = prompt
        for subject in subjects {
            guard let noun = words(subject).last else { continue }
            // A compact natural phrase avoids repeating "apple: 1" as another
            // object. Preserve visible color/material adjectives around the noun.
            let pattern = "(?i)\\b(?:(?:a|an|one|single|two|three|four|five|[0-9]+)\\s+)?((?:(?:red|yellow|green|blue|black|white|brown|pink|orange|small|large|ceramic|wooden|ripe)\\s+){0,4}" + NSRegularExpression.escapedPattern(for: noun) + "s?)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            guard regex.numberOfMatches(in: result, range: range) == 1,
                  let match = regex.firstMatch(in: result, range: range),
                  let objectRange = Range(match.range, in: result),
                  let nounRange = Range(match.range(at: 1), in: result) else { continue }
            var replacement = String(result[objectRange])
            if let count = number(subject) {
                replacement = (countWords[count] ?? String(count)) + " " + result[nounRange]
            }
            if let position = value(arrangement, for: subject), ["left", "right", "center", "middle"].contains(position.lowercased()) {
                let following = result[objectRange.upperBound...].prefix(24).lowercased()
                if !following.hasPrefix(" on the " + position.lowercased()) && !following.hasPrefix(" to the " + position.lowercased()) {
                    replacement += " on the " + position.lowercased()
                }
            }
            result.replaceSubrange(objectRange, with: replacement)
        }
        return result
    }

    private static func words(_ value: String) -> [String] {
        let numbers = ["one": "1", "single": "1", "two": "2", "three": "3", "four": "4", "five": "5"]
        return value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !["a", "an", "the", "and", "of", "on", "in", "with"].contains($0) }
            .map { word in
                if let number = numbers[word] { return number }
                if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
                return word
            }
    }
}
