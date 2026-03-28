//
//  AppLaunchView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2026/01/05.
//


import SwiftUI

struct AppLaunchView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        VStack(spacing: 28) {

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text(
                localizedText(
                    languageCode: selectedLanguage,
                    ja: "AIモデルを準備中…",
                    en: "Preparing AI models…",
                    zh: "正在准备 AI 模型…"
                )
            )
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
