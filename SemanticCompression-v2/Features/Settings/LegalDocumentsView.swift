import SwiftUI

struct LegalDocumentsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey)
    private var acceptedPolicyAt = ""

    var body: some View {
        List {
            Section(t(ja: "同意状況", en: "Consent Status")) {
                Text("\(t(ja: "Privacy", en: "Privacy")): \(statusText(acceptedPrivacyVersion))")
                Text("\(t(ja: "Terms", en: "Terms")): \(statusText(acceptedTermsVersion))")
                if !acceptedPolicyAt.isEmpty {
                    Text("\(t(ja: "同意日時", en: "Accepted At")): \(acceptedPolicyAt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(t(ja: "ドキュメント", en: "Documents")) {
                Link(t(ja: "プライバシーポリシー", en: "Privacy Policy"), destination: AppPreferences.privacyPolicyURL)
                Link(t(ja: "利用規約", en: "Terms of Service"), destination: AppPreferences.termsOfServiceURL)
            }

            Section(t(ja: "連絡先", en: "Contact")) {
                Link("support@mim-protocol.com", destination: URL(string: "mailto:support@mim-protocol.com")!)
                Text(t(ja: "不適切なコンテンツや利用者の報告は上記メールへご連絡ください。", en: "Please use the email above to report inappropriate content or users."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(t(ja: "法務", en: "Legal"))
    }

    private func statusText(_ version: String) -> String {
        version.isEmpty
            ? t(ja: "未同意", en: "Not Accepted")
            : "v\(version)"
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
