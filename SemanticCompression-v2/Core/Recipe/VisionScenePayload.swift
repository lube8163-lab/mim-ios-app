import Foundation
import CoreFoundation

/// Accepts the two subject forms observed on the small VLM; all inference stays on device.
nonisolated struct VisionScenePayload: Sendable {
    let subjects: [String]
    let counts: String
    let arrangement: String
    let relationships: String
    let colors: String
    let lighting: String
    let background: String
    let medium: String
    let description: String
    let generationPrompt: String

    static func parse(_ response: String) throws -> Self {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), text.hasSuffix("```"), let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)..<text.index(text.endIndex, offsetBy: -3)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard text.utf8.count <= 32_000, let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecipeError.invalid("写真の説明形式を読み取れませんでした。")
        }
        func clean(_ value: Any?, limit: Int = 600) -> String? {
            guard let value = value as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.count <= limit ? trimmed : nil
        }
        guard let description = clean(json["description"]),
              let prompt = clean(json["generationPrompt"]),
              prompt.lowercased() != "unknown", description.lowercased() != "unknown",
              let rawSubjects = json["subjects"] as? [Any], !rawSubjects.isEmpty, rawSubjects.count <= 20 else {
            throw RecipeError.invalid("写真の説明が不足しています。")
        }
        var subjects: [String] = [], counts: [String] = [], positions: [String] = []
        var relationships: [String] = [], colors: [String] = []
        for subject in rawSubjects {
            if let name = clean(subject, limit: 80), name.lowercased() != "unknown" { subjects.append(name); continue }
            guard let object = subject as? [String: Any], let name = clean(object["name"], limit: 80), name.lowercased() != "unknown" else {
                throw RecipeError.invalid("写真の主題を読み取れませんでした。")
            }
            subjects.append(name)
            if let number = object["count"] as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
               (1...100).contains(number.doubleValue), number.doubleValue.rounded() == number.doubleValue {
                let count = number.intValue
                counts.append("\(name): \(count)")
            }
            if let position = clean(object["arrangement"], limit: 100), position.lowercased() != "unknown" {
                positions.append("\(name): \(position)")
            }
            if let relation = clean(object["relationships"] ?? object["relationship"], limit: 100) {
                relationships.append("\(name): \(relation)")
            }
            if let color = clean(object["color"], limit: 100) { colors.append(color) }
            if let values = object["colors"] as? [String], values.count <= 10 {
                colors += values.compactMap { clean($0, limit: 80) }
            }
        }
        func field(_ key: String, fallback: [String] = []) -> String {
            clean(json[key]) ?? (fallback.isEmpty ? "unknown" : fallback.joined(separator: "; "))
        }
        guard prompt.count <= 1_200, !prompt.contains("<|"), !prompt.contains("[toolcall:") else {
            throw RecipeError.invalid("写真の再現promptが無効です。")
        }
        return .init(subjects: subjects, counts: field("counts", fallback: counts),
            arrangement: field("arrangement", fallback: positions), relationships: field("relationships", fallback: relationships),
            colors: field("colors", fallback: colors), lighting: field("lighting"), background: field("background"),
            medium: field("medium"), description: description, generationPrompt: prompt)
    }
}
