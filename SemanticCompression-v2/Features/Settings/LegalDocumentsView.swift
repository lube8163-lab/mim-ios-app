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
            Section(t(ja: "同意状況", en: "Consent Status", zh: "同意状态")) {
                Text("\(t(ja: "Privacy", en: "Privacy", zh: "隐私")): \(statusText(acceptedPrivacyVersion))")
                Text("\(t(ja: "Terms", en: "Terms", zh: "条款")): \(statusText(acceptedTermsVersion))")
                if !acceptedPolicyAt.isEmpty {
                    Text("\(t(ja: "同意日時", en: "Accepted At", zh: "同意时间")): \(acceptedPolicyAt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(t(ja: "ドキュメント", en: "Documents", zh: "文档")) {
                Link(t(ja: "プライバシーポリシー", en: "Privacy Policy", zh: "隐私政策"), destination: AppPreferences.privacyPolicyURL)
                Link(t(ja: "利用規約", en: "Terms of Service", zh: "使用条款"), destination: AppPreferences.termsOfServiceURL)
            }

            Section(t(ja: "連絡先", en: "Contact", zh: "联系方式")) {
                Link("support@mim-protocol.com", destination: URL(string: "mailto:support@mim-protocol.com")!)
                Text(t(ja: "不適切なコンテンツや利用者の報告は上記メールへご連絡ください。", en: "Please use the email above to report inappropriate content or users.", zh: "如需举报不当内容或用户，请通过上方邮箱联系我们。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(t(ja: "法務", en: "Legal", zh: "法律"))
    }

    private func statusText(_ version: String) -> String {
        version.isEmpty
            ? t(ja: "未同意", en: "Not Accepted", zh: "未同意")
            : "v\(version)"
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
