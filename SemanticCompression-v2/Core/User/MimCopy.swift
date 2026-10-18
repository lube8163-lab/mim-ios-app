import Foundation
import CryptoKit

@MainActor
func mt(_ source: String, _ arguments: CVarArg...) -> String {
    let suffix = SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    let key = "mim.refresh." + suffix
    let language = UserDefaults.standard.string(forKey: AppPreferences.selectedLanguageKey) ?? AppLanguage.preferred.rawValue
    let translated = L10n.tr(key, languageCode: language)
    let format = translated == key ? source : translated
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: language), arguments: arguments)
}
