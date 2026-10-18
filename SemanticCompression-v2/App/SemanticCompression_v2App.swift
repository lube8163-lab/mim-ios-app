import SwiftUI

@main
struct SemanticCompressionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPreferences.selectedLanguageKey) private var selectedLanguage = AppLanguage.preferred.rawValue
    @AppStorage(AppPreferences.onboardingCompletedKey) private var hasCompletedOnboarding = false
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey) private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey) private var acceptedTermsVersion = ""
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var pushNotificationManager = PushNotificationManager.shared
    @StateObject private var modelManager = ModelManager.shared
    @State private var finishedReviewOnboarding = false
    private var review: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-ui-review")
        #else
        false
        #endif
    }
    private var deviceSmoke: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-device-smoke")
        #else
        false
        #endif
    }
    private var reviewOnboarding: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return review && args.contains(where: { $0.hasPrefix("onboarding-") })
        #else
        false
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if deviceSmoke { DeviceGenerationSmokeView() }
                else if reviewOnboarding && !finishedReviewOnboarding { OnboardingFlowView { finishedReviewOnboarding = true } }
                else if review || isOnboardingSatisfied { ContentView() }
                else { OnboardingFlowView { hasCompletedOnboarding = true } }
                #else
                if review || isOnboardingSatisfied { ContentView() }
                else { OnboardingFlowView { hasCompletedOnboarding = true } }
                #endif
            }
            .task {
                _ = ImageCacheManager.shared
                guard !review, !deviceSmoke else { return }
                await authManager.restoreIfNeeded()
                #if DEBUG
                do { try SocialValidationLog.importSessionIfRequested() }
                catch { SocialValidationLog.record("validationSessionFailed", ["error": error.localizedDescription]) }
                #endif
                await pushNotificationManager.handleAuthenticationStateChanged(isAuthenticated: authManager.isAuthenticated)
                #if DEBUG
                await SocialValidationLog.snapshot()
                #endif
            }
            .onChange(of: authManager.isAuthenticated) { _, authenticated in
                guard !review, !deviceSmoke else { return }
                Task { await pushNotificationManager.handleAuthenticationStateChanged(isAuthenticated: authenticated) }
            }
            .onChange(of: selectedLanguage) { _, _ in
                guard !review, !deviceSmoke else { return }
                Task { await pushNotificationManager.handleLanguageChanged() }
            }
            .environmentObject(modelManager)
            .environmentObject(authManager)
            .environmentObject(pushNotificationManager)
            .environment(\.locale, Locale(identifier: selectedLanguage))
            .tint(MimStyle.accent)
            .preferredColorScheme(review ? (ProcessInfo.processInfo.arguments.contains("--mim-ui-review-dark") ? .dark : .light) : nil)
        }
    }
    private var isOnboardingSatisfied: Bool {
        hasCompletedOnboarding && acceptedPrivacyVersion == AppPreferences.currentPrivacyVersion
            && acceptedTermsVersion == AppPreferences.currentTermsVersion
    }
}
