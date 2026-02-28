import Foundation
import SwiftUI

func localizedText(
    languageCode: String,
    ja: String,
    en: String
) -> String {
    languageCode.hasPrefix(AppLanguage.english.rawValue) ? en : ja
}

extension View {
    func t(_ languageCode: String, ja: String, en: String) -> String {
        localizedText(languageCode: languageCode, ja: ja, en: en)
    }
}
