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
        .navigationTitle(t(ja: "プロフィール", en: "Profile", zh: "个人资料"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t(ja: "閉じる", en: "Close", zh: "关闭")) { dismiss() }
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
                    Text(profile?.displayName ?? t(ja: "読み込み中…", en: "Loading...", zh: "加载中…"))
                        .font(.title3.weight(.bold))
                }

                Spacer()
            }

            HStack(spacing: 18) {
                statView(value: profile?.postCount ?? 0, labelJA: "投稿", labelEN: "Posts", labelZH: "帖子")
                statView(value: profile?.followerCount ?? 0, labelJA: "フォロワー", labelEN: "Followers", labelZH: "粉丝")
                statView(value: profile?.followingCount ?? 0, labelJA: "フォロー中", labelEN: "Following", labelZH: "关注中")
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
                             ? t(ja: "フォロー解除", en: "Unfollow", zh: "取消关注")
                             : t(ja: "フォロー", en: "Follow", zh: "关注"))
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
                Text(t(ja: "投稿", en: "Posts", zh: "帖子"))
                    .font(.headline)
                Spacer()
                if isLoadingPosts {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)

            if !isLoadingPosts && posts.isEmpty {
                Text(t(ja: "まだ投稿はありません", en: "No posts yet", zh: "还没有帖子"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        PostCardView(
                            post: post,
                            isModelInstalled: modelManager.sdInstalled,
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
            errorMessage = t(ja: "プロフィールの取得に失敗しました", en: "Failed to load profile", zh: "加载个人资料失败")
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
                errorMessage = t(ja: "フォロー状態の更新に失敗しました", en: "Failed to update follow state", zh: "更新关注状态失败")
            }
        }
    }

    private func statView(value: Int, labelJA: String, labelEN: String, labelZH: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.bold))
            Text(t(ja: labelJA, en: labelEN, zh: labelZH))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
