import SwiftUI

struct LegalDocumentsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey)
    private var acceptedPolicyAt = ""

    var body: some View {
        List {
            Section(l("legal.consent_status")) {
                Text("\(l("legal.privacy")): \(statusText(acceptedPrivacyVersion))")
                Text("\(l("legal.terms")): \(statusText(acceptedTermsVersion))")
                if !acceptedPolicyAt.isEmpty {
                    Text("\(l("legal.accepted_at")): \(acceptedPolicyAt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(l("legal.documents")) {
                Link(l("legal.privacy_policy"), destination: AppPreferences.privacyPolicyURL)
                Link(l("legal.terms_of_service"), destination: AppPreferences.termsOfServiceURL)
            }

            Section(l("legal.contact")) {
                Link("support@mim-protocol.com", destination: URL(string: "mailto:support@mim-protocol.com")!)
                Text(l("legal.contact_note"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(l("legal.title"))
    }

    private func statusText(_ version: String) -> String {
        version.isEmpty
            ? l("legal.not_accepted")
            : "v\(version)"
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
