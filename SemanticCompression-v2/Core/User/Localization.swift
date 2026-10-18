import Foundation

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
        let preferredCode = AppLanguage.resolve(languageCode).rawValue
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

}
