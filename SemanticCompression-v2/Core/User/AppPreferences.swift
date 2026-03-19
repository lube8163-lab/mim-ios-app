import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        }
    }
}

enum AppPreferences {
    static let selectedLanguageKey = "selected_app_language"
    static let selectedPrivacyModeKey = "selected_privacy_mode"
    static let selectedSDModelKey = "selected_sd_model"
    static let selectedImageUnderstandingModelKey = "selected_image_understanding_model"
    static let proModeEnabledKey = "pro_mode_enabled"
    static let proModeCacheLimitMBKey = "pro_mode_cache_limit_mb"
    static let onboardingCompletedKey = "onboarding_completed"
    static let acceptedPrivacyVersionKey = "accepted_privacy_version"
    static let acceptedTermsVersionKey = "accepted_terms_version"
    static let acceptedPolicyAtKey = "accepted_policy_at"

    static let currentPrivacyVersion = "2026-02-08"
    static let currentTermsVersion = "2026-02-08"

    static let privacyPolicyURL = URL(
        string: "https://lube8163-lab.github.io/mim-ios/privacy.html"
    )!
    static let termsOfServiceURL = URL(
        string: "https://lube8163-lab.github.io/mim-ios/terms.html"
    )!
}

extension Notification.Name {
    static let semanticCacheMaintenanceRequested = Notification.Name("semantic_cache_maintenance_requested")
}
