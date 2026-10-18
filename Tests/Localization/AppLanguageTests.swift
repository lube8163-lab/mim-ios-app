import XCTest
@testable import MimLocalization

final class AppLanguageTests: XCTestCase {
    func testDeviceRegionAliasesResolveToSupportedLanguages() {
        let cases: [(String, AppLanguage)] = [
            ("ja-JP", .japanese), ("JA_jp", .japanese), ("en-US", .english),
            ("es-MX", .spanish), ("pt-PT", .portugueseBrazil), ("PT_BR", .portugueseBrazil),
            ("ko-KR", .korean), ("zh-CN", .chineseSimplified), ("zh-SG", .chineseSimplified),
            ("zh-TW", .chineseTraditional), ("zh-HK", .chineseTraditional), ("zh-MO", .chineseTraditional),
            ("zh-Hant-CN", .chineseTraditional), ("zh-Hans-HK", .chineseSimplified),
            ("zh", .chineseSimplified), ("fr-FR", .english), ("", .english)
        ]
        for (identifier, expected) in cases {
            XCTAssertEqual(AppLanguage.resolve(identifier), expected, identifier)
        }
    }
}
