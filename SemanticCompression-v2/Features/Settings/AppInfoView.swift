//
//  AppInfoView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct AppInfoView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Semantic Compression")
                    .font(.title2)
                    .bold()

                Text(t(
                    ja: """
                    このアプリは、画像を「意味情報（セマンティクス）」として扱い、
                    必要に応じて再構成・再生成することを目的とした、
                    研究・実験的なSNSアプリです。

                    画像そのものではなく、
                    視覚的特徴、意味的タグ、テキスト表現を組み合わせて扱います。
                    """,
                    en: """
                    Semantic Compression is an experimental social app that explores
                    treating images as semantic representations rather than raw data.
                    """
                ))

                Text(t(
                    ja: """
                    本アプリはオンデバイス処理を中心に設計されています。
                    投稿時にはプライバシーモードを選択でき、低解像度初期画像（L4）や
                    非画像の中間表現（L1/L2/L3）を使い分けて生成品質と保護強度を調整できます。
                    """,
                    en: """
                    The app focuses on on-device processing and user-initiated generation.
                    At post time, you can choose a privacy mode including a low-resolution initial-image mode (L4)
                    or non-image intermediate representations (L1/L2/L3), balancing reconstruction and privacy.
                    """
                ))

                Text(t(
                    ja: "生成結果はモデル提供元によって保証・推奨されるものではありません。",
                    en: "Generated content is not endorsed or guaranteed by model providers."
                ))

                Text(t(ja: "リンク", en: "Links"))
                    .font(.headline)

                Link(
                    "GitHub Repository",
                    destination: URL(string: "https://github.com/lube8163-lab/mim-ios/tree/main")!
                )
            }

            .padding()
        }
        .navigationTitle(t(ja: "アプリの説明", en: "App Info"))
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
