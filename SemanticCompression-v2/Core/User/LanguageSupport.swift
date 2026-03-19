import Foundation
import SwiftUI

func localizedText(
    languageCode: String,
    ja: String,
    en: String,
    zh: String? = nil
) -> String {
    if languageCode.hasPrefix(AppLanguage.japanese.rawValue) {
        return ja
    }
    if languageCode.hasPrefix(AppLanguage.chineseSimplified.rawValue) {
        return zh ?? en
    }
    return en
}

extension View {
    func t(_ languageCode: String, ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: languageCode, ja: ja, en: en, zh: zh)
    }
}
