import SwiftUI

enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    func title(languageCode: String) -> String {
        switch self {
        case .privacy:
            return L10n.tr("legal.privacy_policy", languageCode: languageCode)
        case .terms:
            return L10n.tr("legal.terms_of_service", languageCode: languageCode)
        }
    }

    var version: String {
        switch self {
        case .privacy:
            return AppPreferences.currentPrivacyVersion
        case .terms:
            return AppPreferences.currentTermsVersion
        }
    }
}

struct LegalDocumentDetailView: View {
    let kind: LegalDocumentKind
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    init(kind: LegalDocumentKind, showsCloseButton: Bool = false) {
        self.kind = kind
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                ForEach(copy.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)

                        Text(section.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L10n.tr("legal.summary.notice", languageCode: selectedLanguage))
                    .font(.footnote).foregroundStyle(.secondary)
                Link(L10n.tr("legal.summary.full_document", languageCode: selectedLanguage),
                     destination: kind == .privacy ? AppPreferences.privacyPolicyURL : AppPreferences.termsOfServiceURL)
                Text(copy.footer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(MimStyle.paper)
        .navigationTitle(kind.title(languageCode: selectedLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("new_post.close", languageCode: selectedLanguage)) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title(languageCode: selectedLanguage))
                .font(.title2.weight(.bold))

            Text(copy.versionLabel)
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MimStyle.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var copy: LegalDocumentCopy {
        LegalDocumentCopy.document(kind: kind, languageCode: selectedLanguage)
    }
}

struct LegalDocumentSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

struct LegalDocumentCopy {
    let versionLabel: String
    let sections: [LegalDocumentSection]
    let footer: String

    static func document(kind: LegalDocumentKind, languageCode: String) -> LegalDocumentCopy {
        func l(_ key: String, _ arguments: CVarArg...) -> String {
            L10n.tr("legal.summary." + key, languageCode: languageCode, arguments: arguments)
        }
        let keys = kind == .privacy ? ["data", "use", "storage", "controls"] : ["requirements", "posts", "prohibited", "changes"]
        return .init(versionLabel: l("version", kind.version),
            sections: keys.map { .init(title: l($0 + ".title"), body: l($0 + ".body")) },
            footer: l("contact", "support@mim-protocol.com"))
    }
}
