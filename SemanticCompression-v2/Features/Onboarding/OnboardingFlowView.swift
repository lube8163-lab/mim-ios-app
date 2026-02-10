import SwiftUI

struct OnboardingFlowView: View {

    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey)
    private var acceptedPolicyAt = ""

    @State private var acceptedPrivacy = false
    @State private var acceptedTerms = false

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(t(ja: "言語", en: "Language")) {
                    Picker(t(ja: "アプリの言語", en: "App Language"), selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(t(ja: "法務", en: "Legal")) {
                    Toggle(t(ja: "プライバシーポリシーに同意", en: "I agree to the Privacy Policy"), isOn: $acceptedPrivacy)
                    Link(t(ja: "プライバシーポリシーを開く", en: "Open Privacy Policy"), destination: AppPreferences.privacyPolicyURL)

                    Toggle(t(ja: "利用規約に同意", en: "I agree to the Terms of Service"), isOn: $acceptedTerms)
                    Link(t(ja: "利用規約を開く", en: "Open Terms of Service"), destination: AppPreferences.termsOfServiceURL)
                }

                Section {
                    Button(t(ja: "開始する", en: "Get Started")) {
                        completeOnboarding()
                    }
                    .disabled(!(acceptedPrivacy && acceptedTerms))
                    .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text(t(ja: "同意は設定画面からいつでも確認できます。", en: "You can review consent status from Settings anytime."))
                }
            }
            .navigationTitle(t(ja: "ようこそ", en: "Welcome"))
        }
    }

    private func completeOnboarding() {
        acceptedPrivacyVersion = AppPreferences.currentPrivacyVersion
        acceptedTermsVersion = AppPreferences.currentTermsVersion
        acceptedPolicyAt = ISO8601DateFormatter().string(from: Date())
        onComplete()
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
