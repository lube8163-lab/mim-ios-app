import Foundation

nonisolated enum ContentSafetyContext: String, Sendable { case publicText, generationPrompt }

nonisolated enum ContentSafetyError: Error, LocalizedError, Equatable {
    case blocked, unavailable, tooLong
    var errorDescription: String? {
        switch self {
        case .blocked: "この内容は送信・表示できません。内容を確認してください。"
        case .unavailable: "内容の安全性を確認できません。時間を置いて再試行してください。"
        case .tooLong: "入力内容が長すぎます。短くして再試行してください。"
        }
    }
}

/// Local rules catch explicit patterns; they are not a semantic classifier or a guarantee
/// that all harmful content is detected. The same revision is used by the offline Worker.
nonisolated struct ContentSafetyPolicy: Codable, Sendable {
    struct Rule: Codable, Sendable {
        let id: String
        let category: String
        let contexts: [String]
        let groups: [[String]]
        let maxSpan: Int
    }
    let version: Int
    let revision: String
    let supportedLanguages: [String]
    let maxUTF16Length: Int
    let benignPhrases: [String]
    let rules: [Rule]

    private static let loaded: Result<Self, Error> = Result {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "ContentSafetyPolicy", withExtension: "json") else {
            throw ContentSafetyError.unavailable
        }
        do { return try decode(Data(contentsOf: url)) }
        catch { throw ContentSafetyError.unavailable }
    }

    static func bundled() throws -> Self { try loaded.get() }

    static func decode(_ data: Data) throws -> Self {
        let policy = try JSONDecoder().decode(Self.self, from: data)
        guard policy.version == 1, policy.revision == "mim-content-20261012-v1",
              policy.maxUTF16Length == 4000, !policy.rules.isEmpty,
              Set(policy.rules.map(\.id)).count == policy.rules.count else {
            throw ContentSafetyError.unavailable
        }
        for rule in policy.rules {
            guard !rule.groups.isEmpty, rule.groups.allSatisfy({ !$0.isEmpty }),
                  (1...4000).contains(rule.maxSpan), !rule.contexts.isEmpty,
                  rule.contexts.allSatisfy({ ContentSafetyContext(rawValue: $0) != nil }) else {
                throw ContentSafetyError.unavailable
            }
            for pattern in rule.groups.flatMap({ $0 }) {
                guard !pattern.isEmpty else { throw ContentSafetyError.unavailable }
                _ = try NSRegularExpression(pattern: pattern)
            }
        }
        return policy
    }

    static func normalize(_ input: String) -> String {
        let folded = input.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let withoutControls = folded.unicodeScalars.filter { $0.properties.generalCategory != .format }
        let lookalikes: [Character: Character] = ["а":"a", "е":"e", "о":"o", "р":"p", "с":"c", "х":"x", "у":"y", "і":"i"]
        return String(String.UnicodeScalarView(withoutControls)).map { String(lookalikes[$0] ?? $0) }.joined()
    }

    func validate(_ text: String?, context: ContentSafetyContext = .publicText) throws {
        guard let text else { return }
        guard text.utf16.count <= maxUTF16Length else { throw ContentSafetyError.tooLong }
        var normalized = Self.normalize(text)
        // Remove only these exact, benign expressions, never the remainder of a message.
        for phrase in benignPhrases {
            normalized = normalized.replacingOccurrences(of: Self.normalize(phrase), with: " ")
        }
        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for rule in rules where rule.contexts.contains(context.rawValue) {
            let matches: [[NSRange]] = try rule.groups.map { group in
                try group.flatMap { pattern in
                    try NSRegularExpression(pattern: pattern).matches(in: normalized, range: fullRange).map(\.range)
                }
            }
            guard matches.allSatisfy({ !$0.isEmpty }) else { continue }
            let starts = matches.flatMap { $0.map(\.location) }
            if starts.contains(where: { start in
                matches.allSatisfy { group in group.contains { $0.location >= start && NSMaxRange($0) <= start + rule.maxSpan } }
            }) { throw ContentSafetyError.blocked }
        }
    }

    func permits(_ text: String?, context: ContentSafetyContext = .publicText) -> Bool {
        (try? validate(text, context: context)) != nil
    }

    static func displayText(_ text: String?, fallback: String = "") -> String {
        guard let policy = try? bundled(), policy.permits(text) else { return fallback }
        return text ?? fallback
    }
}
