//
//  SemanticCompressionApp.swift
//  SemanticCompressionApp
//
//  Created by Tasuku Kato on 2025/10/21.
//

import SwiftUI

@main
struct SemanticCompressionApp: App {

    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.onboardingCompletedKey)
    private var hasCompletedOnboarding = false
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""

    @StateObject private var taggerHolder = TaggerHolder()
    @StateObject private var authManager = AuthManager.shared

    @StateObject private var modelManager =
        ModelManager()

    init() {
        Task.detached(priority: .utility) {

            let isInstalled = await MainActor.run {
                ModelManager.shared.siglipInstalled
            }

            if isInstalled {
                try? await SigLIP2Service.shared.loadIfNeeded()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isOnboardingSatisfied {
                    ContentView()
                        .task {
                            taggerHolder.loadAll()
                        }
                } else {
                    OnboardingFlowView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .task {
                await authManager.restoreIfNeeded()
            }
            .environmentObject(taggerHolder)
            .environmentObject(modelManager)
            .environmentObject(authManager)
            .environment(\.locale, Locale(identifier: selectedLanguage))
        }
    }

    private var isOnboardingSatisfied: Bool {
        hasCompletedOnboarding
            && acceptedPrivacyVersion == AppPreferences.currentPrivacyVersion
            && acceptedTermsVersion == AppPreferences.currentTermsVersion
    }
}
