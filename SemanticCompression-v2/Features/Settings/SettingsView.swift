//
//  SettingsView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        List {
            Section(t(ja: "表示", en: "Display")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Text(t(ja: "言語設定", en: "Language"))
                }

                NavigationLink {
                    PrivacyModeSettingsView()
                } label: {
                    Text(t(ja: "投稿モード", en: "Post Mode"))
                }
            }

            Section(t(ja: "このアプリについて", en: "About")) {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(t(ja: "アプリの説明", en: "App Info"))
                }
            }

            Section(t(ja: "ライセンス", en: "Licenses")) {
                NavigationLink {
                    LicenseView()
                } label: {
                    Text(t(ja: "使用モデルとライセンス", en: "Models and Licenses"))
                }
            }

            Section(t(ja: "法務", en: "Legal")) {
                NavigationLink {
                    LegalDocumentsView()
                } label: {
                    Text(t(ja: "プライバシーポリシー / 利用規約", en: "Privacy Policy / Terms"))
                }
            }
        }
        .navigationTitle(t(ja: "設定", en: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
