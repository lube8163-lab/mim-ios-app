import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    @EnvironmentObject private var auth: AuthManager
    @State private var confirmCache = false
    @State private var confirmLogout = false
    var body: some View {
        let _ = language
        List {
            Section {
                NavigationLink(mt("言語")) { LanguageSettingsView() }.accessibilityIdentifier("settings-language")
                NavigationLink(mt("モデル管理")) { ModelManagementView() }.accessibilityIdentifier("settings-models")
                NavigationLink(mt("詳細設定")) { GenerationDisplaySettingsView() }.accessibilityIdentifier("settings-advanced")
                Button(mt("再現画像のキャッシュを消去"), role: .destructive) { confirmCache = true }
            }
            Section {
                NavigationLink(mt("ブロックしたユーザー")) { BlockedUsersView() }
                NavigationLink(mt("アプリについて")) { AppInfoView() }.accessibilityIdentifier("settings-about")
                NavigationLink(mt("プライバシーと利用規約")) { LegalDocumentsView() }
                NavigationLink(mt("ライセンス")) { LicenseView() }.accessibilityIdentifier("settings-licenses")
            }
            if auth.isAuthenticated {
                Section {
                    Button(mt("ログアウト"), role: .destructive) { confirmLogout = true }
                        .mimLogoutConfirmation(isPresented: $confirmLogout) { Task { await auth.logout() } }
                }
            }
        }.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(MimStyle.paper)
            .navigationTitle(mt("設定")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(mt("再現画像のキャッシュを消去しますか？"), isPresented: $confirmCache) {
                Button(mt("消去"), role: .destructive) {
                    NotificationCenter.default.post(name: .semanticCacheMaintenanceRequested, object: nil)
                }
            }
    }
}

private struct GenerationDisplaySettingsView: View {
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    @AppStorage(AppPreferences.showsGenerationPromptKey) private var showsPrompt = false
    var body: some View {
        let _ = language
        List {
            Section {
                Toggle(mt("生成用プロンプトを表示"), isOn: $showsPrompt)
                    .accessibilityIdentifier("generation-prompt-toggle")
            } footer: {
                Text(mt("投稿の下に生成用の英文を表示します。通常は表示する必要はありません。"))
            }
        }.scrollContentBackground(.hidden).background(MimStyle.paper)
            .navigationTitle(mt("詳細設定")).navigationBarTitleDisplayMode(.inline)
    }
}
