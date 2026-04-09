import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    var body: some View {
        Form {
            Section(L10n.tr("settings.language.display_language", languageCode: selectedLanguage)) {
                Picker("", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        }
        .navigationTitle(L10n.tr("settings.language.title", languageCode: selectedLanguage))
    }
}
