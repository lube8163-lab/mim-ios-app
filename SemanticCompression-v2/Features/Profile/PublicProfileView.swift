import SwiftUI

struct PublicProfileView: View {
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var profile: PublicUserProfile?
    @State private var posts: [Post] = []
    @State private var isLoadingPosts = false
    @State private var isUpdatingFollow = false
    @State private var errorMessage: String?
    @State private var showLoginSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                }

                postsSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(l("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(l("profile.close")) { dismiss() }
            }
        }
        .task {
            await loadAll()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .generationPriorityChanged, object: [Post](), userInfo: ["postIDs": []])
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AsyncImage(url: URL(string: profile?.avatarUrl ?? "")) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color.gray.opacity(0.16))
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.displayName ?? l("profile.loading"))
                        .font(.title3.weight(.bold))

                    if let bio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !bio.isEmpty {
                        Text(bio)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }

            HStack(spacing: 18) {
                statView(value: profile?.postCount ?? 0, label: l("profile.posts"))
                statView(value: profile?.followerCount ?? 0, label: l("profile.followers"))
                statView(value: profile?.followingCount ?? 0, label: l("profile.following"))
            }

            if shouldShowFollowButton {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    if isUpdatingFollow {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text((profile?.isFollowing ?? false)
                             ? l("profile.unfollow")
                             : l("profile.follow"))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(l("profile.posts"))
                    .font(.headline)
                Spacer()
                if isLoadingPosts {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)

            if !isLoadingPosts && posts.isEmpty {
                Text(l("profile.no_posts"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        PostCardView(
                            post: post,
                            isModelInstalled: modelManager.canGenerateImages,
                            priorityContextPostIDs: posts.map(\.id)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var shouldShowFollowButton: Bool {
        authManager.isAuthenticated && userId != UserManager.shared.currentUser.id
    }

    @MainActor
    private func loadAll() async {
        do {
            profile = try await FollowService.fetchPublicProfile(userId: userId)
            isLoadingPosts = true
            defer { isLoadingPosts = false }
            posts = try await FeedLoader.fetchMyPosts(userId: userId, page: 0, pageSize: 20)
            NotificationCenter.default.post(
                name: .generationPriorityChanged,
                object: posts,
                userInfo: ["postIDs": posts.map(\.id)]
            )
        } catch {
            errorMessage = l("profile.error.load_failed")
        }
    }

    @MainActor
    private func toggleFollow() async {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }
        guard let profile else { return }

        isUpdatingFollow = true
        defer { isUpdatingFollow = false }

        do {
            if profile.isFollowing {
                try await FollowService.unfollow(userId: userId)
            } else {
                try await FollowService.follow(userId: userId)
            }
            self.profile = try await FollowService.fetchPublicProfile(userId: userId)
        } catch {
            let message = error.localizedDescription
            if !message.isEmpty, message != URLError(.badServerResponse).localizedDescription {
                errorMessage = message
            } else {
                errorMessage = l("profile.error.follow_failed")
            }
        }
    }

    private func statView(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
