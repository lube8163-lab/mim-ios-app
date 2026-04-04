import CoreGraphics
import Foundation

struct AppleVisionPromptPayload {
    let prompt: String
    let concepts: [String]
    let tags: [String]
}

struct AppleVisionAnalyzedTag: Hashable {
    let label: String
    let confidence: Float
    let scope: String
    let location: CGPoint
}

struct PromptSafetyPolicy: Decodable {
    struct ReplacementRule: Decodable {
        let pattern: String
        let replacement: String
    }

    let hardBlockedTagGroups: [String: [String]]
    let softBlockedTagGroups: [String: [String]]
    let strictTriggerGroups: [String: [String]]
    let hardBlockedPromptTermGroups: [String: [String]]
    let softBlockedPromptTermGroups: [String: [String]]
    let replacementRules: [ReplacementRule]
    let cleanupRules: [ReplacementRule]

    var hardBlockedTagLabels: Set<String> {
        Set(hardBlockedTagGroups.values.flatMap { $0 })
    }

    var softBlockedTagLabels: Set<String> {
        Set(softBlockedTagGroups.values.flatMap { $0 })
    }

    var strictTagTriggers: Set<String> {
        Set(strictTriggerGroups.values.flatMap { $0 })
    }

    var hardBlockedPromptTerms: [String] {
        hardBlockedPromptTermGroups.values.flatMap { $0 }
    }

    var softBlockedPromptTerms: [String] {
        softBlockedPromptTermGroups.values.flatMap { $0 }
    }

    static func loadDefault(bundle: Bundle = .main) -> PromptSafetyPolicy {
        guard
            let url = bundle.url(forResource: "prompt_safety_policy", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let policy = try? JSONDecoder().decode(PromptSafetyPolicy.self, from: data)
        else {
            return fallback
        }
        return policy
    }

    private static let fallback = PromptSafetyPolicy(
        hardBlockedTagGroups: [
            "people": ["adult", "people", "person", "human", "child"],
            "safety": ["nude", "blood", "weapon", "logo", "hate"]
        ],
        softBlockedTagGroups: [
            "noise": ["clothing", "material", "textile", "liquid", "structure", "frozen", "pattern", "design", "product", "font", "text", "display", "screen", "graphic", "illustration", "snapshot", "rectangle", "circle", "line", "event", "fun", "smile", "light"]
        ],
        strictTriggerGroups: [
            "people": ["adult", "people", "person", "human", "child", "man", "woman"]
        ],
        hardBlockedPromptTermGroups: [
            "people": ["people", "person", "human", "adult", "child", "baby", "toddler", "woman", "man", "girl", "boy", "bride"],
            "safety": ["nude", "blood", "weapon", "gun", "knife", "hate", "racism"]
        ],
        softBlockedPromptTermGroups: [
            "people": ["people", "person", "human", "adult", "child", "baby", "toddler", "kid", "kids", "woman", "man", "girl", "boy", "family", "parent", "mother", "father", "bride", "groom", "guest", "guests", "musician", "musicians", "climber", "climbing", "swimmer", "swimming", "playing", "drinking", "eating", "smiling", "portrait", "selfie"]
        ],
        replacementRules: [
            .init(pattern: "small band rehearsal", replacement: "music studio scene"),
            .init(pattern: "band rehearsal", replacement: "music studio scene"),
            .init(pattern: "single climber", replacement: "mountain scene"),
            .init(pattern: "rock climbing", replacement: "rock wall scene"),
            .init(pattern: "pool, water", replacement: "poolside water scene"),
            .init(pattern: "swimming pool", replacement: "pool")
        ],
        cleanupRules: [
            .init(pattern: " featuring .", replacement: "."),
            .init(pattern: " featuring ,", replacement: ","),
            .init(pattern: "featuring interior room", replacement: "featuring an interior room scene"),
            .init(pattern: "featuring poolside water scene", replacement: "featuring a poolside water scene"),
            .init(pattern: "featuring recreation, rock wall scene", replacement: "featuring a rock wall scene"),
            .init(pattern: "featuring ,", replacement: "featuring "),
            .init(pattern: "with .", replacement: "."),
            .init(pattern: "with ,", replacement: ","),
            .init(pattern: "Place .", replacement: ""),
            .init(pattern: "Place ,", replacement: ""),
            .init(pattern: "  ", replacement: " "),
            .init(pattern: " ,", replacement: ","),
            .init(pattern: ", .", replacement: "."),
            .init(pattern: ". .", replacement: ".")
        ]
    )
}

struct AppleImagePromptComposer {
    private let builder: ImagePromptBuilder
    private let sanitizer: PromptSanitizer

    init(policy: PromptSafetyPolicy = .loadDefault()) {
        self.builder = ImagePromptBuilder(policy: policy)
        self.sanitizer = PromptSanitizer(policy: policy)
    }

    func makePayload(tags: [AppleVisionAnalyzedTag], usesSourceImage: Bool) -> AppleVisionPromptPayload {
        let draft = builder.makePrompt(from: tags, usesSourceImage: usesSourceImage)
        return sanitizer.sanitize(draft, tags: tags, usesSourceImage: usesSourceImage)
    }

    func sanitizePrompt(prompt: String, tags: [String], usesSourceImage: Bool) -> AppleVisionPromptPayload {
        let analyzed = tags.enumerated().map { index, label in
            AppleVisionAnalyzedTag(
                label: label.lowercased(),
                confidence: Float(max(0, 100 - index)),
                scope: "global",
                location: CGPoint(x: 0.5, y: 0.5)
            )
        }
        let payload = AppleVisionPromptPayload(prompt: prompt, concepts: [prompt], tags: tags)
        return sanitizer.sanitize(payload, tags: analyzed, usesSourceImage: usesSourceImage)
    }
}

private struct ImagePromptBuilder {
    let policy: PromptSafetyPolicy

    func makePrompt(from tags: [AppleVisionAnalyzedTag], usesSourceImage: Bool) -> AppleVisionPromptPayload {
        let sorted = tags.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.label < rhs.label
            }
            return lhs.confidence > rhs.confidence
        }
        let filtered = sorted.filter {
            !policy.hardBlockedTagLabels.contains($0.label) && !policy.softBlockedTagLabels.contains($0.label)
        }
        let rawLabels = Set(tags.map(\.label))
        let isUIScreen = !rawLabels.isDisjoint(with: ["screenshot", "document", "display", "screen", "text", "font"])
        let globalLabels = uniqueLabels(from: filtered.filter { $0.scope == "global" }, limit: 3)
        let localTags = prioritizedLocalTags(from: filtered.filter { $0.scope != "global" }, limit: 4)

        let subjectPhrase = subjectDescription(
            globalLabels: globalLabels,
            usesSourceImage: usesSourceImage,
            isUIScreen: isUIScreen,
            rawLabels: rawLabels
        )
        let compositionPhrase = compositionDescription(
            localTags: localTags,
            isUIScreen: isUIScreen,
            rawLabels: rawLabels
        )
        let prompt = promptText(
            subjectPhrase: subjectPhrase,
            compositionPhrase: compositionPhrase,
            usesSourceImage: usesSourceImage,
            isUIScreen: isUIScreen
        )

        let concepts = conceptList(
            subjectPhrase: subjectPhrase,
            compositionPhrase: compositionPhrase,
            usesSourceImage: usesSourceImage,
            isUIScreen: isUIScreen
        ).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let stableTags = (globalLabels + localTags.map { displayLabel(for: $0.label) })
            .map { $0.lowercased() }

        return AppleVisionPromptPayload(prompt: prompt, concepts: concepts, tags: Array(NSOrderedSet(array: stableTags)) as? [String] ?? stableTags)
    }

    private func subjectDescription(globalLabels: [String], usesSourceImage: Bool, isUIScreen: Bool, rawLabels: Set<String>) -> String {
        if isUIScreen {
            return "a clean settings-style interface with simple cards, toggles, and labels"
        }
        if let generalized = generalizedSubject(from: globalLabels, rawLabels: rawLabels) {
            return generalized
        }
        if globalLabels.isEmpty {
            return usesSourceImage ? "a simplified scene from the source image" : "a simple, readable scene with clear shapes"
        }
        return globalLabels.joined(separator: ", ")
    }

    private func compositionDescription(localTags: [AppleVisionAnalyzedTag], isUIScreen: Bool, rawLabels: Set<String>) -> String {
        if isUIScreen {
            return "Use a neat vertical layout with grouped cards and generous spacing."
        }
        if let generalized = generalizedComposition(localTags: localTags, rawLabels: rawLabels) {
            return generalized
        }
        return localTags.isEmpty
            ? "Keep the composition simple and readable."
            : "Place " + localTags.map { "\(displayLabel(for: $0.label)) near the \(positionDescription(for: $0.location))" }.joined(separator: ", ") + "."
    }

    private func promptText(subjectPhrase: String, compositionPhrase: String, usesSourceImage: Bool, isUIScreen: Bool) -> String {
        let opener: String
        if isUIScreen {
            opener = "Create a polished illustration of \(subjectPhrase)."
        } else if usesSourceImage {
            opener = "Create a polished image based on the source image featuring \(subjectPhrase)."
        } else {
            opener = "Create a polished image featuring \(subjectPhrase)."
        }

        let closer: String
        if isUIScreen {
            closer = "Keep the interface minimal, legible, and visually balanced."
        } else if usesSourceImage {
            closer = "Preserve the overall arrangement of the scene while simplifying details and keeping subjects recognizable."
        } else {
            closer = "Keep the result simple, coherent, and easy to read."
        }

        return [opener, compositionPhrase, closer].joined(separator: " ")
    }

    private func conceptList(subjectPhrase: String, compositionPhrase: String, usesSourceImage: Bool, isUIScreen: Bool) -> [String] {
        let leadConcept: String
        if isUIScreen {
            leadConcept = "clean mobile interface"
        } else if usesSourceImage {
            leadConcept = "source image scene"
        } else {
            leadConcept = "clean illustration"
        }

        let finishConcept = isUIScreen
            ? "minimal layout, readable labels, soft colors"
            : "clean composition, coherent lighting"

        return [leadConcept, subjectPhrase, compositionPhrase, finishConcept]
    }

    private func containsPeopleHints(in labels: Set<String>) -> Bool {
        !labels.isDisjoint(with: ["people", "person", "human", "adult", "child", "man", "woman"])
    }

    private func generalizedSubject(from globalLabels: [String], rawLabels: Set<String>) -> String? {
        let hasPeople = containsPeopleHints(in: rawLabels)
        let hasBuilding = !rawLabels.isDisjoint(with: ["building", "tower", "skyscraper", "city", "cityscape"])
        let hasSnow = !rawLabels.isDisjoint(with: ["snow", "ice", "mountain", "ridge", "glacier"])
        let hasMusic = !rawLabels.isDisjoint(with: ["music", "musical_instrument", "drum", "guitar", "speaker", "speakers_music", "microphone"])
        let hasNight = rawLabels.contains("night_sky")
        let hasWater = !rawLabels.isDisjoint(with: ["water", "fountain", "river", "sea", "harbor"])

        if hasBuilding && hasNight {
            return hasWater ? "a nighttime urban scene with buildings and water" : "a nighttime urban scene with illuminated buildings"
        }
        if hasSnow {
            return hasPeople ? "a snowy mountain scene under a clear sky" : "a snowy mountain landscape under a clear sky"
        }
        if hasMusic {
            return hasPeople ? "a music studio scene with instruments" : "an indoor music scene with instruments"
        }
        if hasBuilding {
            return "an architectural scene with buildings"
        }
        if !globalLabels.isEmpty {
            return globalLabels.joined(separator: ", ")
        }
        return nil
    }

    private func generalizedComposition(localTags: [AppleVisionAnalyzedTag], rawLabels: Set<String>) -> String? {
        let hasPeople = containsPeopleHints(in: rawLabels)
        let skyPosition = groupedPosition(for: localTags, families: ["sky"])
        let landPosition = groupedPosition(for: localTags, families: ["landform", "outdoor"])
        let instrumentPosition = groupedPosition(for: localTags, families: ["instrument"])
        let buildingPosition = groupedPosition(for: localTags, families: ["building"])
        let waterPosition = groupedPosition(for: localTags, families: ["water"])

        if !rawLabels.isDisjoint(with: ["snow", "ice", "mountain", "ridge", "glacier"]) {
            var parts: [String] = []
            if let landPosition {
                parts.append("Keep the landforms toward the \(landPosition)")
            }
            if let skyPosition {
                parts.append("leave open sky toward the \(skyPosition)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ").capitalized + "."
        }

        if !rawLabels.isDisjoint(with: ["music", "musical_instrument", "drum", "guitar", "speaker", "speakers_music", "microphone"]) {
            var parts: [String] = []
            if let instrumentPosition {
                parts.append("Place the main instruments near the \(instrumentPosition)")
            }
            parts.append(hasPeople ? "avoid describing specific people" : "keep the arrangement focused on equipment")
            return parts.joined(separator: ", ").capitalized + "."
        }

        if !rawLabels.isDisjoint(with: ["building", "tower", "skyscraper", "city", "cityscape"]) {
            var parts: [String] = []
            if let buildingPosition {
                parts.append("Keep the buildings near the \(buildingPosition)")
            }
            if let skyPosition {
                parts.append("leave the sky toward the \(skyPosition)")
            }
            if let waterPosition {
                parts.append("place water or reflections near the \(waterPosition)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ").capitalized + "."
        }

        return nil
    }

    private func uniqueLabels(from tags: [AppleVisionAnalyzedTag], limit: Int) -> [String] {
        var seen: Set<String> = []
        var labels: [String] = []

        for tag in tags where !seen.contains(tag.label) {
            seen.insert(tag.label)
            labels.append(displayLabel(for: tag.label))
            if labels.count == limit {
                break
            }
        }

        return labels
    }

    private func prioritizedLocalTags(from tags: [AppleVisionAnalyzedTag], limit: Int) -> [AppleVisionAnalyzedTag] {
        let sorted = tags.sorted { lhs, rhs in
            let lhsPriority = localPriority(for: lhs.label)
            let rhsPriority = localPriority(for: rhs.label)
            if lhsPriority == rhsPriority {
                if lhs.confidence == rhs.confidence {
                    return lhs.label < rhs.label
                }
                return lhs.confidence > rhs.confidence
            }
            return lhsPriority > rhsPriority
        }

        var seen: Set<String> = []
        var output: [AppleVisionAnalyzedTag] = []

        for tag in sorted {
            let family = labelFamily(for: tag.label)
            guard !seen.contains(family) else { continue }
            seen.insert(family)
            output.append(tag)
            if output.count == limit {
                break
            }
        }

        return output
    }

    private func localPriority(for label: String) -> Int {
        switch labelFamily(for: label) {
        case "subject": 5
        case "landform", "building", "instrument": 4
        case "sky", "water", "snow", "indoor", "outdoor": 3
        default: 1
        }
    }

    private func labelFamily(for label: String) -> String {
        switch label {
        case "sky", "blue_sky", "night_sky", "cloud", "outdoor":
            return "sky"
        case "snow", "ice", "mountain", "ridge", "glacier", "rocks":
            return "landform"
        case "building", "skyscraper", "tower", "city", "cityscape":
            return "building"
        case "music", "musical_instrument", "drum", "guitar", "microphone", "speaker", "speakers_music", "tripod":
            return "instrument"
        case "water", "fountain", "river", "sea", "harbor", "pool":
            return "water"
        case "indoor", "room", "studio", "interior_room":
            return "indoor"
        case "landscape":
            return "outdoor"
        case "person", "people", "human", "adult", "child":
            return "subject"
        default:
            return label
        }
    }

    private func displayLabel(for label: String) -> String {
        switch label {
        case "speakers_music": return "speakers"
        case "night_sky": return "night sky"
        case "blue_sky": return "blue sky"
        case "interior_room": return "interior room"
        default:
            return label.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func groupedPosition(for tags: [AppleVisionAnalyzedTag], families: Set<String>) -> String? {
        let matches = tags.filter { families.contains(labelFamily(for: $0.label)) }
        guard !matches.isEmpty else { return nil }
        let avgX = matches.map(\.location.x).reduce(0, +) / CGFloat(matches.count)
        let avgY = matches.map(\.location.y).reduce(0, +) / CGFloat(matches.count)
        return positionDescription(for: CGPoint(x: avgX, y: avgY))
    }

    private func positionDescription(for point: CGPoint) -> String {
        let horizontal: String
        switch point.x {
        case ..<0.34: horizontal = "left"
        case 0.67...: horizontal = "right"
        default: horizontal = "center"
        }

        let vertical: String
        switch point.y {
        case ..<0.34: vertical = "top"
        case 0.67...: vertical = "bottom"
        default: vertical = "middle"
        }

        if horizontal == "center" { return vertical }
        if vertical == "middle" { return horizontal }
        return "\(vertical) \(horizontal)"
    }
}

private struct PromptSanitizer {
    let policy: PromptSafetyPolicy

    func sanitize(_ payload: AppleVisionPromptPayload, tags: [AppleVisionAnalyzedTag], usesSourceImage: Bool) -> AppleVisionPromptPayload {
        let labels = Set(tags.map(\.label))
        let shouldApplyStrictSafety = !usesSourceImage || !labels.isDisjoint(with: policy.strictTagTriggers)

        var prompt = payload.prompt
        var concepts = payload.concepts
        var stableTags = payload.tags

        if shouldApplyStrictSafety {
            prompt = sanitizeText(prompt)
            concepts = concepts.map(sanitizeText)
            stableTags = stableTags.map(sanitizeText)
        }

        prompt = cleanupText(prompt)
        concepts = concepts.map(cleanupText).filter { !$0.isEmpty }
        stableTags = stableTags.map(cleanupText).filter { !$0.isEmpty }

        return .init(
            prompt: prompt,
            concepts: concepts,
            tags: Array(NSOrderedSet(array: stableTags)) as? [String] ?? stableTags
        )
    }

    private func sanitizeText(_ text: String) -> String {
        var output = text

        for rule in policy.replacementRules {
            output = output.replacingOccurrences(of: rule.pattern, with: rule.replacement, options: [.caseInsensitive])
        }

        for term in policy.hardBlockedPromptTerms {
            output = output.replacingOccurrences(of: term, with: "", options: [.caseInsensitive])
        }

        for term in policy.softBlockedPromptTerms {
            output = output.replacingOccurrences(of: term, with: "", options: [.caseInsensitive])
        }

        return cleanupText(output)
    }

    private func cleanupText(_ text: String) -> String {
        var output = text

        for rule in policy.cleanupRules {
            output = output.replacingOccurrences(of: rule.pattern, with: rule.replacement)
        }

        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
