import SwiftUI
import PhotosUI

struct UserProfileView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var userManager = UserManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    // Profile edit
    @State private var newName = ""
    @State private var showCopied = false
    @State private var isSavingChanges = false

    // Avatar upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var accountAlertMessage = ""
    @State private var showAccountAlert = false
    @State private var showLoginSheet = false

    // Account delete
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    let showsCloseButton: Bool

    init(showsCloseButton: Bool = true) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Form {

            // MARK: - USER INFO (read only)
            userInfoSection

            // MARK: - PROFILE EDIT
            profileEditSection

            // MARK: - APP / SETTINGS
            appSettingsSection

            // MARK: - DANGER ZONE
            dangerZoneSection
        }
        .navigationTitle(t(ja: "プロフィール", en: "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseButton)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t(ja: "閉じる", en: "Close")) { dismiss() }
                }
            }
        }
        .alert(t(ja: "コピーしました", en: "Copied!"), isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        }
        .alert(t(ja: "アカウント", en: "Account"), isPresented: $showAccountAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountAlertMessage)
        }
        .confirmationDialog(
            t(ja: "アカウントを削除しますか？", en: "Delete this account?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(t(ja: "削除する", en: "Delete"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
        } message: {
            Text(t(ja: "この操作は取り消せません。投稿は匿名化されます。", en: "This action cannot be undone. Posts will be anonymized."))
        }
        .onAppear {
            newName = userManager.currentUser.displayName
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
        }
    }

    // MARK: - Sections

    private var userInfoSection: some View {
        Section(header: Text(t(ja: "ユーザー", en: "User"))) {
            if !authManager.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t(ja: "現在はゲストモードです", en: "You are in guest mode"))
                        .font(.subheadline.weight(.semibold))
                    Text(t(ja: "ログインすると投稿、いいね、ブロック機能が有効になります。", en: "Sign in to enable posting, likes, and block features."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        showLoginSheet = true
                    } label: {
                        Text(t(ja: "メールでログイン", en: "Sign in with Email"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 16) {

                AsyncImage(
                    url: URL(string: userManager.currentUser.avatarUrl)
                ) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(userManager.currentUser.displayName)
                        .font(.headline)
                    if !userManager.currentUser.id.isEmpty {
                        Text(userManager.currentUser.id)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .contextMenu {
                                Button(t(ja: "ユーザーIDをコピー", en: "Copy User ID")) {
                                    UIPasteboard.general.string =
                                        userManager.currentUser.id
                                    showCopied = true
                                }
                            }
                    }
                    if let email = userManager.currentUser.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var profileEditSection: some View {
        Section {

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                Label(t(ja: "アバターを変更", en: "Change Avatar"), systemImage: "photo")
            }
            if selectedPhoto != nil {
                Text(t(ja: "新しいアバターは保存時に反映されます。", en: "The new avatar will be applied when you save."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField(t(ja: "表示名", en: "Display Name"), text: $newName)

            Button {
                Task { await saveChanges() }
            } label: {
                if isSavingChanges {
                    ProgressView()
                } else {
                    Text(t(ja: "変更を保存", en: "Save Changes"))
                }
            }
            .disabled(isSavingChanges || !hasPendingChanges || !authManager.isAuthenticated)
            .frame(maxWidth: .infinity, alignment: .center)
        } header: {
            Text(t(ja: "アカウント", en: "Account"))
        } footer: {
            Text(
                authManager.isAuthenticated
                ? t(ja: "メール認証済みアカウントです。", en: "Signed in with email OTP.")
                : t(ja: "編集や投稿にはログインが必要です。", en: "Sign in is required for editing and posting.")
            )
        }
    }

    private var appSettingsSection: some View {
        Section(header: Text(t(ja: "アプリ", en: "App"))) {

            NavigationLink {
                SettingsView()
            } label: {
                Label(t(ja: "設定", en: "Settings"), systemImage: "gear")
            }

            NavigationLink {
                ModelManagementView()
            } label: {
                Label("AI Models", systemImage: "cpu")
            }

            NavigationLink {
                BlockedUsersView()
            } label: {
                Label(t(ja: "ブロック管理", en: "Blocked Users"), systemImage: "person.2.slash")
            }
        }
    }

    private var dangerZoneSection: some View {
        Section {
            if authManager.isAuthenticated {
                Button(role: .destructive) {
                    Task { await authManager.logout() }
                } label: {
                    Text(t(ja: "ログアウト", en: "Log Out"))
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(t(ja: "アカウントを削除", en: "Delete Account"))
                }
            } else {
                Button {
                    showLoginSheet = true
                } label: {
                    Text(t(ja: "メールでログイン", en: "Sign in with Email"))
                }
            }
        }
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }

    // MARK: - Avatar Upload

    private func uploadAvatarIfSelected() async throws -> String? {
        guard let item = selectedPhoto else { return nil }

        guard
            let data = try await item.loadTransferable(type: Data.self),
            let original = UIImage(data: data)
        else { return nil }

        let resized = original.resizedSquare(to: 256)
        guard let jpeg = resized.jpegData(compressionQuality: 0.75)
        else { return nil }

        let rawUrl = try await AvatarUploader.uploadAvatar(data: jpeg)

        // cache bust
        let bustedUrl =
            rawUrl + "?v=\(Int(Date().timeIntervalSince1970))"

        #if DEBUG
        print("✅ Avatar uploaded:", bustedUrl)
        #endif

        return bustedUrl
    }

    private func saveChanges() async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = userManager.currentUser

        let nameChanged = !trimmedName.isEmpty && trimmedName != current.displayName
        let avatarChanged = selectedPhoto != nil

        guard nameChanged || avatarChanged else {
            accountAlertMessage = t(ja: "変更はありません。", en: "No changes to save.")
            showAccountAlert = true
            return
        }

        isSavingChanges = true
        defer { isSavingChanges = false }

        var updated = current
        if nameChanged {
            updated.displayName = trimmedName
        }

        do {
            if let newAvatarURL = try await uploadAvatarIfSelected() {
                updated.avatarUrl = newAvatarURL
            }

            userManager.saveUser(updated)
            await UserService.register(updated)
            selectedPhoto = nil
            accountAlertMessage = t(ja: "変更を保存しました。", en: "Changes saved.")
            showAccountAlert = true
            if showsCloseButton { dismiss() }
        } catch {
            accountAlertMessage = t(ja: "保存に失敗しました。時間をおいて再度お試しください。", en: "Save failed. Please try again later.")
            showAccountAlert = true
        }
    }

    private var hasPendingChanges: Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = userManager.currentUser

        let nameChanged = !trimmedName.isEmpty && trimmedName != current.displayName
        let avatarChanged = selectedPhoto != nil
        return nameChanged || avatarChanged
    }

    // MARK: - Delete Account

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await AccountService.deleteAccount()
            authManager.signOutLocal()
            dismiss()
            #if DEBUG
            print("✅ Account deleted")
            #endif
        } catch {
            #if DEBUG
            print("❌ Account delete failed:", error)
            #endif
        }
    }
}

//struct ModelManagementView: View {
//    var body: some View {
//        Text("Model management coming soon")
//            .navigationTitle("AI Models")
//    }
//}
