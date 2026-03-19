import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        Form {
            Section(t(ja: "表示言語", en: "Language", zh: "显示语言")) {
                Picker("", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        }
        .navigationTitle(t(ja: "言語設定", en: "Language", zh: "语言设置"))
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
