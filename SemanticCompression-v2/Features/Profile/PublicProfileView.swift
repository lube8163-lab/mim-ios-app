import SwiftUI

struct PublicProfileView: View {
    let userId: String
    var showsCloseButton = true

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue

    @State private var profile: PublicUserProfile?
    @State private var posts: [Post] = []
    @State private var isLoadingPosts = false
    @State private var isUpdatingFollow = false
    @State private var errorMessage: String?
    @State private var showLoginSheet = false
    @State private var showEditor = false
    private var isReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-ui-review")
        #else
        false
        #endif
    }
    private var isOwnProfile: Bool { isReview || userId == UserManager.shared.currentUser.id }

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
        .background(MimStyle.paper.ignoresSafeArea())
        .navigationTitle(l("profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l("profile.close")) { dismiss() }
                }
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
        .sheet(isPresented: $showEditor, onDismiss: { Task { await loadAll() } }) {
            NavigationStack { UserProfileView(showAppSettings: false) }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                CachedAvatarView(urlString: profile?.avatarUrl ?? "") {
                        ZStack {
                            Circle().fill(MimStyle.soft)
                            Text(String(ContentSafetyPolicy.displayText(profile?.displayName).prefix(1)).uppercased())
                                .font(.system(size: 30, weight: .medium)).foregroundStyle(.secondary)
                        }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                Spacer()
                if isOwnProfile {
                    Button(mt("プロフィールを編集")) { showEditor = true }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                        .overlay(Capsule().stroke(MimStyle.line, lineWidth: 1)).buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                    Text(ContentSafetyPolicy.displayText(profile?.displayName, fallback: l("profile.loading")))
                        .font(.title2.weight(.semibold))

                    if let bio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !bio.isEmpty {
                        Text(ContentSafetyPolicy.displayText(bio))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
            }

            HStack(spacing: 18) {
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
                .buttonStyle(MimPrimaryButtonStyle())
            }
            MimStyle.line.frame(height: 0.5)
        }
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
                        ).padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }

    private var shouldShowFollowButton: Bool {
        authManager.isAuthenticated && !isOwnProfile
    }

    @MainActor
    private func loadAll() async {
        #if DEBUG
        if isReview {
            profile = .init(id: userId, displayName: "haru", avatarUrl: "", bio: "日々の景色と、ちょっとしたこと。",
                            followerCount: 42, followingCount: 38, postCount: 3, isFollowing: false)
            posts = UIReviewFixtures.posts()
            return
        }
        #endif
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
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
