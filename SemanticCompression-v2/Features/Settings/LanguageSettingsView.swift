import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    var body: some View {
        List {
            Section(L10n.tr("settings.language.display_language", languageCode: selectedLanguage)) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        selectedLanguage = language.rawValue
                    } label: {
                        HStack {
                            Text(language.label).foregroundStyle(.primary)
                            Spacer()
                            if AppLanguage.resolve(selectedLanguage) == language {
                                Image(systemName: "checkmark").foregroundStyle(MimStyle.accent)
                            }
                        }.frame(minHeight: 30)
                    }
                    .accessibilityIdentifier("language-" + language.rawValue)
                    .accessibilityAddTraits(AppLanguage.resolve(selectedLanguage) == language ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(MimStyle.paper)
        .navigationTitle(L10n.tr("settings.language.title", languageCode: selectedLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("language-settings")
    }
}
