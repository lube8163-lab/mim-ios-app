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
    @State private var newBio = ""
    @State private var showCopied = false
    @State private var isSavingChanges = false

    // Avatar upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var accountAlertMessage = ""
    @State private var showAccountAlert = false
    @State private var showLoginSheet = false

    // Account delete
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    let showsCloseButton: Bool
    let showAppSettings: Bool

    init(showsCloseButton: Bool = true, showAppSettings: Bool = true) {
        self.showsCloseButton = showsCloseButton
        self.showAppSettings = showAppSettings
    }

    var body: some View {
        Form {

            // MARK: - USER INFO (read only)
            userInfoSection

            // MARK: - PROFILE EDIT
            profileEditSection

            // MARK: - APP / SETTINGS
            if showAppSettings {
                appSettingsSection
            }

            // MARK: - DANGER ZONE
            dangerZoneSection
        }
        .navigationTitle(l("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseButton)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l("profile.close")) { dismiss() }
                }
            }
        }
        .alert(l("profile.alert.copied"), isPresented: $showCopied) {
            Button("OK", role: .cancel) {}
        }
        .alert(l("profile.account"), isPresented: $showAccountAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accountAlertMessage)
        }
        .alert(
            l("profile.alert.logout.title"),
            isPresented: $showLogoutConfirm
        ) {
            Button(l("profile.log_out"), role: .destructive) {
                Task { await authManager.logout() }
            }
            Button(l("common.cancel"), role: .cancel) {}
        } message: {
            Text(l("content.alert.logout.message"))
        }
        .confirmationDialog(
            l("profile.alert.delete_account.title"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(l("profile.delete_account"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(l("common.cancel"), role: .cancel) {}
        } message: {
            Text(l("profile.alert.delete_account.message"))
        }
        .onAppear {
            newName = userManager.currentUser.displayName
            newBio = userManager.currentUser.bio
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
        }
    }

    // MARK: - Sections

    private var userInfoSection: some View {
        Section(header: Text(l("profile.user"))) {
            if !authManager.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l("profile.guest_mode"))
                        .font(.subheadline.weight(.semibold))
                    Text(l("profile.guest_mode_detail"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        showLoginSheet = true
                    } label: {
                        Text(l("profile.sign_in_with_email"))
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
                    if !userManager.currentUser.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(userManager.currentUser.bio)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !userManager.currentUser.id.isEmpty {
                        Text(userManager.currentUser.id)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .contextMenu {
                                Button(l("profile.copy_user_id")) {
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
                Label(l("profile.change_avatar"), systemImage: "photo")
            }
            if selectedPhoto != nil {
                Text(l("profile.change_avatar_note"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextField(l("profile.display_name"), text: $newName)

            TextField(l("profile.bio"), text: $newBio, axis: .vertical)
                .lineLimit(2...4)

            Text(l("profile.bio_limit"))
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                Task { await saveChanges() }
            } label: {
                if isSavingChanges {
                    ProgressView()
                } else {
                    Text(l("profile.save_changes"))
                }
            }
            .disabled(isSavingChanges || !hasPendingChanges || !authManager.isAuthenticated)
            .frame(maxWidth: .infinity, alignment: .center)
        } header: {
            Text(l("profile.account"))
        } footer: {
            Text(
                authManager.isAuthenticated
                ? l("profile.email_otp_signed_in")
                : l("profile.sign_in_required")
            )
        }
    }

    private var appSettingsSection: some View {
        Section(header: Text(l("profile.app"))) {

            NavigationLink {
                SettingsView()
            } label: {
                Label(l("profile.settings"), systemImage: "gear")
            }

            NavigationLink {
                ModelManagementView()
            } label: {
                Label("AI Models", systemImage: "cpu")
            }

            NavigationLink {
                BlockedUsersView()
            } label: {
                Label(l("profile.blocked.title"), systemImage: "person.2.slash")
            }
        }
    }

    private var dangerZoneSection: some View {
        Section {
            if authManager.isAuthenticated {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text(l("profile.log_out"))
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(l("profile.delete_account"))
                }
            } else {
                Button {
                    showLoginSheet = true
                } label: {
                    Text(l("profile.sign_in_with_email"))
                }
            }
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
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
        let trimmedBio = String(newBio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let current = userManager.currentUser

        let nameChanged = !trimmedName.isEmpty && trimmedName != current.displayName
        let bioChanged = trimmedBio != current.bio
        let avatarChanged = selectedPhoto != nil

        guard nameChanged || bioChanged || avatarChanged else {
            accountAlertMessage = l("profile.alert.no_changes")
            showAccountAlert = true
            return
        }

        isSavingChanges = true
        defer { isSavingChanges = false }

        var updated = current
        if nameChanged {
            updated.displayName = trimmedName
        }
        if bioChanged {
            updated.bio = trimmedBio
        }

        do {
            if let newAvatarURL = try await uploadAvatarIfSelected() {
                updated.avatarUrl = newAvatarURL
            }

            userManager.saveUser(updated)
            await UserService.register(updated)
            selectedPhoto = nil
            accountAlertMessage = l("profile.alert.saved")
            showAccountAlert = true
            if showsCloseButton { dismiss() }
        } catch {
            accountAlertMessage = l("profile.alert.save_failed")
            showAccountAlert = true
        }
    }

    private var hasPendingChanges: Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = String(newBio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let current = userManager.currentUser

        let nameChanged = !trimmedName.isEmpty && trimmedName != current.displayName
        let bioChanged = trimmedBio != current.bio
        let avatarChanged = selectedPhoto != nil
        return nameChanged || bioChanged || avatarChanged
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
