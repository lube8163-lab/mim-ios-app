import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case spanish = "es"
    case portugueseBrazil = "pt-BR"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .spanish: return "Español"
        case .portugueseBrazil: return "Português (Brasil)"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        }
    }

    /// Use the same BCP-47 resolution for device preferences and explicit lookups.
    static func resolve(_ identifier: String) -> AppLanguage {
        let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
        switch parts.first {
        case "ja": return .japanese
        case "es": return .spanish
        case "pt": return .portugueseBrazil
        case "ko": return .korean
        case "zh":
            if parts.contains("hant") { return .chineseTraditional }
            if parts.contains("hans") { return .chineseSimplified }
            return parts.contains(where: { ["tw", "hk", "mo"].contains($0) })
                ? .chineseTraditional : .chineseSimplified
        default: return .english
        }
    }

    static var preferred: AppLanguage {
        resolve(Locale.preferredLanguages.first ?? Locale.current.identifier)
    }
}

enum AppPreferences {
    static let selectedLanguageKey = "selected_app_language"
    static let selectedSDModelKey = "selected_sd_model"
    static let onboardingCompletedKey = "onboarding_completed"
    static let acceptedPrivacyVersionKey = "accepted_privacy_version"
    static let acceptedTermsVersionKey = "accepted_terms_version"
    static let acceptedPolicyAtKey = "accepted_policy_at"
    static let showsGenerationPromptKey = "shows_generation_prompt_v1"

    static let currentPrivacyVersion = "2026-10-11"
    static let currentTermsVersion = "2026-10-11"

    static let privacyPolicyURL = URL(
        string: "https://lube8163-lab.github.io/mim-ios/privacy.html"
    )!
    static let termsOfServiceURL = URL(
        string: "https://lube8163-lab.github.io/mim-ios/terms.html"
    )!
}

extension Notification.Name {
    static let semanticCacheMaintenanceRequested = Notification.Name("semantic_cache_maintenance_requested")
    static let regenerateImagesRequested = Notification.Name("regenerate_images_requested")
    static let generationPriorityChanged = Notification.Name("generation_priority_changed")
    static let regenerateSinglePostRequested = Notification.Name("regenerate_single_post_requested")
    static let postDeleted = Notification.Name("post_deleted")
    static let postReported = Notification.Name("post_reported")
    static let deferStableDiffusionReloadUntilRestart = Notification.Name("defer_stable_diffusion_reload_until_restart")
}
