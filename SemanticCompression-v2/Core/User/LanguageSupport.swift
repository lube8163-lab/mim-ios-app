import Foundation

func localizedText(
    languageCode: String,
    ja: String,
    en: String
) -> String {
    languageCode.hasPrefix(AppLanguage.english.rawValue) ? en : ja
}
