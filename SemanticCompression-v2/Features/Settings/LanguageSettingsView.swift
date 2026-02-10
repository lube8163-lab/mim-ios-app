import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        Form {
            Section(t(ja: "表示言語", en: "Language")) {
                Picker(t(ja: "言語", en: "Language"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(t(ja: "言語設定", en: "Language"))
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
