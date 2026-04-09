//
//  AppLaunchView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2026/01/05.
//


import SwiftUI

struct AppLaunchView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    var body: some View {
        VStack(spacing: 28) {

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text(L10n.tr("app.launch.preparing_ai_models", languageCode: selectedLanguage))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
