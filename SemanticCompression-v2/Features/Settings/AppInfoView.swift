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
            VStack(alignment: .leading, spacing: 28) {

                Text("Semantic Compression")
                    .font(.title2)
                    .bold()

                infoSection(
                    titleKey: "app_info.overview.title",
                    bodyKey: "app_info.overview.body"
                )

                infoSection(
                    titleKey: "app_info.image_understanding.title",
                    bodyKey: "app_info.image_understanding.body"
                )

                infoSection(
                    titleKey: "app_info.image_generation.title",
                    bodyKey: "app_info.image_generation.body"
                )

                infoSection(
                    titleKey: "app_info.ai_backend_labels.title",
                    bodyKey: "app_info.ai_backend_labels.body"
                )

                infoSection(
                    titleKey: "app_info.post_modes.title",
                    bodyKey: "app_info.post_modes.body"
                )

                infoSection(
                    titleKey: "app_info.pro_mode.title",
                    bodyKey: "app_info.pro_mode.body"
                )

                Text(l("app_info.disclaimer"))

                Text(l("app_info.links"))
                    .font(.headline)

                Link(
                    l("app_info.github_repository"),
                    destination: URL(string: "https://github.com/lube8163-lab/mim-ios/tree/main")!
                )
            }

            .padding()
        }
        .navigationTitle(l("app_info.navigation_title"))
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }

    @ViewBuilder
    private func infoSection(
        titleKey: String,
        bodyKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l(titleKey))
                .font(.headline)
            Text(l(bodyKey))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
