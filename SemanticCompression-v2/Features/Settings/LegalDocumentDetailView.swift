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

                Text(copy.footer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        let isJapanese = languageCode.hasPrefix(AppLanguage.japanese.rawValue)
        switch (kind, isJapanese) {
        case (.privacy, true):
            return .init(
                versionLabel: "バージョン \(kind.version)",
                sections: [
                    .init(
                        title: "扱うデータ",
                        body: "このアプリは、投稿内容、画像から抽出した caption / prompt / tags、いいね、ブロック、ログイン情報、端末上の設定を扱います。元画像そのものを常に送信する設計ではなく、投稿モードに応じて軽量な意味情報を送信します。"
                    ),
                    .init(
                        title: "利用目的",
                        body: "データは、投稿の表示、画像の再生成、アカウント認証、不正利用の防止、問い合わせ対応、サービス改善のために使います。AI モデルの出力は、端末や選択中 backend によって変わる場合があります。"
                    ),
                    .init(
                        title: "保存と共有",
                        body: "投稿に必要な情報はサーバーに保存されます。端末内のモデル、キャッシュ、設定は端末上に保持されます。法令上必要な場合、または安全な運用に必要な場合を除き、個人情報を第三者へ販売しません。"
                    ),
                    .init(
                        title: "ユーザーの操作",
                        body: "設定画面から表示言語、投稿モード、AI backend、キャッシュ関連の設定を変更できます。投稿、ブロック、通報などの操作はアプリ内から行えます。"
                    )
                ],
                footer: "お問い合わせ: support@mim-protocol.com"
            )

        case (.terms, true):
            return .init(
                versionLabel: "バージョン \(kind.version)",
                sections: [
                    .init(
                        title: "利用条件",
                        body: "このアプリを利用することで、本規約とプライバシーポリシーに同意したものとみなします。投稿、いいね、ブロックなど一部の機能はログイン後に利用できます。"
                    ),
                    .init(
                        title: "投稿と再生成",
                        body: "投稿画像は、投稿モードや AI backend に応じて意味情報へ変換され、閲覧側の端末で再生成されます。再生成結果は元画像と完全には一致せず、端末やモデル設定によって変わります。"
                    ),
                    .init(
                        title: "禁止事項",
                        body: "違法な内容、他者の権利を侵害する内容、嫌がらせ、なりすまし、過度に性的または暴力的な内容、サービスの妨害、不正アクセス、AI 生成機能の悪用は禁止します。"
                    ),
                    .init(
                        title: "変更と停止",
                        body: "安全性や運用上の理由により、機能の変更、投稿の非表示、アカウント制限、サービスの一時停止を行う場合があります。重要な変更がある場合は、アプリ内または配布ページで案内します。"
                    )
                ],
                footer: "お問い合わせ: support@mim-protocol.com"
            )

        case (.privacy, false):
            return .init(
                versionLabel: "Version \(kind.version)",
                sections: [
                    .init(
                        title: "Data We Handle",
                        body: "The app handles post content, captions, prompts, tags, likes, blocks, sign-in data, and local app settings. Original images are not always sent as-is; posts are uploaded as lightweight meaning data according to the selected posting mode."
                    ),
                    .init(
                        title: "How We Use Data",
                        body: "Data is used to display posts, regenerate images, authenticate accounts, prevent abuse, respond to support requests, and improve the service. AI output may vary by device and selected backend."
                    ),
                    .init(
                        title: "Storage and Sharing",
                        body: "Information required for posts is stored on the server. Local models, caches, and settings remain on the device. We do not sell personal information to third parties except where legally required or necessary for safe operation."
                    ),
                    .init(
                        title: "Your Controls",
                        body: "You can change display language, posting mode, AI backend, and cache-related settings from the Settings screen. Posting, blocking, and reporting actions are available in the app."
                    )
                ],
                footer: "Contact: support@mim-protocol.com"
            )

        case (.terms, false):
            return .init(
                versionLabel: "Version \(kind.version)",
                sections: [
                    .init(
                        title: "Use of the App",
                        body: "By using this app, you agree to these terms and the Privacy Policy. Some features, including posting, likes, and blocks, require sign-in."
                    ),
                    .init(
                        title: "Posts and Regeneration",
                        body: "Posted images are converted into meaning data according to the selected posting mode and AI backend, then regenerated on the viewer's device. Results may not match the original image and can vary by device or model settings."
                    ),
                    .init(
                        title: "Prohibited Conduct",
                        body: "You may not post illegal content, infringe others' rights, harass others, impersonate people, submit excessively sexual or violent content, disrupt the service, attempt unauthorized access, or abuse AI generation features."
                    ),
                    .init(
                        title: "Changes and Suspension",
                        body: "For safety or operational reasons, we may change features, hide posts, limit accounts, or temporarily suspend the service. Important changes will be communicated in the app or on the distribution page."
                    )
                ],
                footer: "Contact: support@mim-protocol.com"
            )
        }
    }
}
