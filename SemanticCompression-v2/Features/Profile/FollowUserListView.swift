import SwiftUI

struct FollowUserListView: View {
    let kind: FollowListKind

    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    @State private var users: [FollowListUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, users.isEmpty {
                ContentUnavailableView {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                }
            } else if users.isEmpty {
                ContentUnavailableView(
                    emptyMessage,
                    systemImage: "person.2",
                    description: Text(title)
                )
            } else {
                List(users) { user in
                    NavigationLink {
                        PublicProfileView(userId: user.id)
                    } label: {
                        followUserRow(for: user)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard users.isEmpty else { return }
            await loadUsers()
        }
        .refreshable {
            await loadUsers()
        }
    }

    private func followUserRow(for user: FollowListUser) -> some View {
        HStack(spacing: 12) {
            CachedAvatarView(urlString: user.avatarUrl) {
                Circle()
                    .fill(Color.gray.opacity(0.18))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(ContentSafetyPolicy.displayText(user.displayName, fallback: l("profile.unknown_user")))
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)

                if let bio = user.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    Text(ContentSafetyPolicy.displayText(bio))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            users = try await FollowService.fetchUsers(kind: kind)
        } catch {
            users = []
            errorMessage = l("profile.error.load_failed")
        }
    }

    private var title: String {
        switch kind {
        case .followers:
            return l("profile.followers")
        case .following:
            return l("profile.following")
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .followers:
            return l("profile.followers_empty")
        case .following:
            return l("profile.following_empty")
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
