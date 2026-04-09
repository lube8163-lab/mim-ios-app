import Foundation
import SwiftUI

enum L10n {
    static func tr(
        _ key: String,
        languageCode: String,
        arguments: [CVarArg]
    ) -> String {
        let format = tr(key, languageCode: languageCode)

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    static func tr(
        _ key: String,
        languageCode: String,
        fallback: String? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let bundle = bundle(for: languageCode)
        let fallbackValue = fallback ?? englishBundle.localizedString(forKey: key, value: key, table: nil)
        let format = bundle.localizedString(forKey: key, value: fallbackValue, table: nil)

        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: languageCode), arguments: arguments)
    }

    private static func bundle(for languageCode: String) -> Bundle {
        let preferredCode = normalizedLanguageCode(for: languageCode)
        if let path = Bundle.main.path(forResource: preferredCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static var englishBundle: Bundle {
        if let path = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    private static func normalizedLanguageCode(for languageCode: String) -> String {
        if languageCode.hasPrefix(AppLanguage.japanese.rawValue) {
            return AppLanguage.japanese.rawValue
        }
        if languageCode.hasPrefix(AppLanguage.spanish.rawValue) {
            return AppLanguage.spanish.rawValue
        }
        if languageCode.hasPrefix(AppLanguage.portugueseBrazil.rawValue)
            || languageCode.hasPrefix("pt-BR")
            || languageCode.hasPrefix("pt") {
            return AppLanguage.portugueseBrazil.rawValue
        }
        if languageCode.hasPrefix(AppLanguage.korean.rawValue) {
            return AppLanguage.korean.rawValue
        }
        if languageCode.hasPrefix(AppLanguage.chineseSimplified.rawValue) {
            return AppLanguage.chineseSimplified.rawValue
        }
        if languageCode.hasPrefix(AppLanguage.chineseTraditional.rawValue) {
            return AppLanguage.chineseTraditional.rawValue
        }
        return AppLanguage.english.rawValue
    }
}
