import SwiftUI

struct PostDetailView: View {
    @ObservedObject var post: Post
    let isModelInstalled: Bool
    var restorePriorityPostIDs: [String]? = nil

    @EnvironmentObject private var authManager: AuthManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var comments: [PostComment] = []
    @State private var isLoading = false
    @State private var composerText = ""
    @State private var isSubmitting = false
    @State private var showLoginSheet = false
    @State private var errorMessage: String?
    @State private var replyTarget: PostComment?
    @State private var selectedProfileUserID: String?

    private let maxCommentLength = 240

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PostCardView(
                    post: post,
                    isModelInstalled: isModelInstalled,
                    showsCommentButton: false,
                    allowsDetailNavigation: false
                )

                commentSection
            }
            .padding(16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(t(ja: "投稿", en: "Post", zh: "帖子"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModelInstalled && post.hasImage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t(ja: "再生成", en: "Regenerate", zh: "重新生成")) {
                        NotificationCenter.default.post(
                            name: .regenerateSinglePostRequested,
                            object: post,
                            userInfo: ["postID": post.id]
                        )
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
                .background(.ultraThinMaterial)
        }
        .task {
            await loadComments()
        }
        .onAppear {
            NotificationCenter.default.post(
                name: .generationPriorityChanged,
                object: [post],
                userInfo: ["postIDs": [post.id]]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .generationPriorityChanged,
                object: [Post](),
                userInfo: ["postIDs": restorePriorityPostIDs ?? []]
            )
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
        }
        .sheet(isPresented: Binding(
            get: { selectedProfileUserID != nil },
            set: { if !$0 { selectedProfileUserID = nil } }
        )) {
            if let selectedProfileUserID {
                NavigationStack {
                    PublicProfileView(userId: selectedProfileUserID)
                }
            }
        }
    }

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t(ja: "コメント", en: "Comments", zh: "评论"))
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            if !isLoading && comments.isEmpty {
                Text(t(ja: "まだコメントはありません", en: "No comments yet", zh: "还没有评论"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(threadedComments) { entry in
                    CommentRowView(
                        comment: entry.comment,
                        languageCode: selectedLanguage,
                        depth: entry.depth,
                        onOpenProfile: {
                            openProfile(for: entry.comment)
                        },
                        onReply: {
                            replyTarget = entry.comment
                        }
                    )
                }
            }
        }
    }

    private var composerBar: some View {
        VStack(spacing: 10) {
            if !authManager.isAuthenticated {
                Button {
                    showLoginSheet = true
                } label: {
                    Text(t(ja: "ログインしてコメント", en: "Sign in to comment", zh: "登录后评论"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            } else {
                if let replyTarget {
                    HStack(spacing: 8) {
                        Text(
                            t(
                                ja: "@\(replyTarget.displayName ?? "User") に返信中",
                                en: "Replying to @\(replyTarget.displayName ?? "User")"
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                        Spacer()

                        Button(t(ja: "キャンセル", en: "Cancel", zh: "取消")) {
                            self.replyTarget = nil
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 16)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField(
                        t(ja: "コメントを書く", en: "Write a comment", zh: "写评论"),
                        text: $composerText,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onChange(of: composerText) { _, newValue in
                        if newValue.count > maxCommentLength {
                            composerText = String(newValue.prefix(maxCommentLength))
                        }
                    }

                    Button {
                        Task { await submitComment() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(t(ja: "送信", en: "Send", zh: "发送"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .padding(.bottom, 10)
    }

    @MainActor
    private func loadComments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            comments = try await CommentService.fetchComments(postId: post.id)
            post.commentCount = comments.count
        } catch {
            errorMessage = t(ja: "コメントの読み込みに失敗しました", en: "Failed to load comments", zh: "加载评论失败")
        }
    }

    @MainActor
    private func submitComment() async {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }

        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let created = try await CommentService.postComment(
                postId: post.id,
                text: trimmed,
                parentCommentId: replyTarget?.id
            )
            comments.append(created)
            composerText = ""
            replyTarget = nil
            post.commentCount = comments.count
        } catch {
            errorMessage = t(ja: "コメントの送信に失敗しました", en: "Failed to send comment", zh: "发送评论失败")
        }
    }

    private var threadedComments: [CommentThreadEntry] {
        let grouped = Dictionary(grouping: comments, by: \.parentCommentId)
        let roots = (grouped[nil] ?? []).sorted { $0.createdAt < $1.createdAt }

        func appendChildren(
            of parentId: String,
            depth: Int,
            into result: inout [CommentThreadEntry]
        ) {
            let children = (grouped[parentId] ?? []).sorted { $0.createdAt < $1.createdAt }
            for child in children {
                result.append(CommentThreadEntry(comment: child, depth: depth))
                appendChildren(of: child.id, depth: depth + 1, into: &result)
            }
        }

        var result: [CommentThreadEntry] = []
        for root in roots {
            result.append(CommentThreadEntry(comment: root, depth: 0))
            appendChildren(of: root.id, depth: 1, into: &result)
        }
        return result
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }

    private func openProfile(for comment: PostComment) {
        guard !comment.userId.isEmpty else { return }
        guard comment.userId != UserManager.shared.currentUser.id else { return }
        selectedProfileUserID = comment.userId
    }
}

private struct CommentThreadEntry: Identifiable {
    let comment: PostComment
    let depth: Int

    var id: String { comment.id }
}

private struct CommentRowView: View {
    let comment: PostComment
    let languageCode: String
    let depth: Int
    let onOpenProfile: () -> Void
    let onReply: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpenProfile) {
                AsyncImage(url: URL(string: comment.avatarUrl ?? "")) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.18))
                            .overlay(
                                Text(initial)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: onOpenProfile) {
                        Text(comment.displayName ?? localizedText(languageCode: languageCode, ja: "ユーザー", en: "User", zh: "用户"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    Text(relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                Button(action: onReply) {
                    Text(localizedText(languageCode: languageCode, ja: "返信", en: "Reply", zh: "回复"))
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.leading, CGFloat(min(depth, 6)) * 18)
    }

    private var initial: String {
        let name = comment.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (name?.isEmpty == false) ? name! : "U"
        return String(base.prefix(1)).uppercased()
    }

    private var relativeTime: String {
        ServerDate.relativeString(from: comment.createdAt, languageCode: languageCode)
    }
}
