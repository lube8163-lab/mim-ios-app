//
//  LicenseView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct LicenseView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Group {
                    Text(l("license.models_used"))
                        .font(.headline)

                    Text(l("license.models_used.body"))
                }

                Group {
                    Text(l("license.about"))
                        .font(.headline)

                    Text(l("license.about.body"))
                }
            }
            .padding()
        }
        .navigationTitle(l("license.title"))
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
