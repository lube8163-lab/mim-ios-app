//
//  AppInfoView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct AppInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Semantic Compression")
                    .font(.title2)
                    .bold()

                Text("""
            このアプリは、画像を「意味情報（セマンティクス）」として扱い、
            必要に応じて再構成・再生成することを目的とした、
            研究・実験的なSNSアプリです。

            画像そのものではなく、
            視覚的特徴、意味的タグ、テキスト表現を組み合わせて扱います。
            """)

                Text("""
            本アプリは、オンデバイス処理を中心に設計されており、
            ユーザー操作を起点とした生成のみを行います。
            """)

                Text("English")
                    .font(.headline)

                Text("""
            Semantic Compression is an experimental social app that explores
            treating images as semantic representations rather than raw data.

            The app focuses on on-device processing and user-initiated generation.
            Generated content is not endorsed or guaranteed by model providers.
            """)

                Text("Links")
                    .font(.headline)

                Link(
                    "GitHub Repository",
                    destination: URL(string: "https://github.com/lube8163-lab/mim-ios/tree/main")!
                )
            }

            .padding()
        }
        .navigationTitle("アプリの説明")
    }
}
