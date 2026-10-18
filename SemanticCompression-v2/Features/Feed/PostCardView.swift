import SwiftUI
import Combine

struct PostCardView: View {

    @ObservedObject var post: Post
    let isModelInstalled: Bool
    var showsCommentButton: Bool = true
    var allowsDetailNavigation: Bool = true
    var priorityContextPostIDs: [String]? = nil
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authManager: AuthManager
    var onUserBlocked: ((String) -> Void)? = nil
    var onPostReported: ((String) -> Void)? = nil
    var onPostDeleted: ((String) -> Void)? = nil
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue
    @AppStorage(AppPreferences.showsGenerationPromptKey) private var showsGenerationPrompt = false

    @State private var showShare = false

    // 🚨 Report UI states
    @State private var showReportDialog = false
    @State private var showReportThanks = false
    @State private var showReportError = false
    @State private var showBlockConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var showLoginSheet = false
    @State private var showCaptionDetail = false
    @State private var showComments = false
    @State private var showAuthorProfile = false

    var body: some View {
        content
            .sheet(isPresented: $showShare) {
                shareSheet
            }
            .sheet(isPresented: $showLoginSheet) {
                OTPLoginView(allowsSkip: true)
            }
            .sheet(isPresented: $showComments) {
                NavigationStack {
                    PostDetailView(
                        post: post,
                        isModelInstalled: isModelInstalled,
                        restorePriorityPostIDs: priorityContextPostIDs
                    )
                }
            }
            .sheet(isPresented: $showAuthorProfile) {
                NavigationStack {
                    if let userId = post.userId, !userId.isEmpty {
                        PublicProfileView(userId: userId)
                    }
                }
            }
            .confirmationDialog(
                l("post_card.dialog.report.title"),
                isPresented: $showReportDialog,
                titleVisibility: .visible
            ) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.label(languageCode: selectedLanguage), role: .destructive) {
                        submitReport(reason)
                    }
                }
                Button(l("common.cancel"), role: .cancel) {}
            }
            .alert(l("post_card.alert.report_submitted.title"), isPresented: $showReportThanks) {
                Button("OK") {}
            } message: {
                Text(l("post_card.alert.report_submitted.message"))
            }
            .alert(
                l("post_card.alert.report_failed.title"),
                isPresented: $showReportError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(l("post_card.alert.try_again_later"))
            }
            .confirmationDialog(
                l("post_card.dialog.block_user.title"),
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(l("post_card.dialog.block_user.confirm"), role: .destructive) {
                    blockAuthorIfNeeded()
                }
                Button(l("common.cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                l("post_card.dialog.delete_post.title"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(l("post_card.dialog.delete_post.confirm"), role: .destructive) {
                    deletePost()
                }
                Button(l("common.cancel"), role: .cancel) {}
            }
            .alert(
                l("post_card.alert.delete_failed.title"),
                isPresented: $showDeleteError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(l("post_card.alert.try_again_later"))
            }
    }
    
    enum ReportReason: String, CaseIterable, Identifiable {
        case inappropriate = "不適切な画像"
        case violence = "暴力・残虐"
        case sexual = "性的コンテンツ"
        case hate = "ヘイト・差別"
        case spam = "スパム"
        case other = "その他"

        var id: String { rawValue }

        func label(languageCode: String) -> String {
            switch self {
            case .inappropriate:
                return L10n.tr("post_card.report_reason.inappropriate", languageCode: languageCode)
            case .violence:
                return L10n.tr("post_card.report_reason.violence", languageCode: languageCode)
            case .sexual:
                return L10n.tr("post_card.report_reason.sexual", languageCode: languageCode)
            case .hate:
                return L10n.tr("post_card.report_reason.hate", languageCode: languageCode)
            case .spam:
                return L10n.tr("post_card.report_reason.spam", languageCode: languageCode)
            case .other:
                return L10n.tr("post_card.report_reason.other", languageCode: languageCode)
            }
        }

        func payload(languageCode: String) -> String {
            label(languageCode: languageCode)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            detailOpenSection.padding(.leading, 48)
            if showsGenerationPrompt, let prompt = post.recipe?.prompt ?? post.semanticPrompt, !prompt.isEmpty {
                DisclosureGroup(mt("生成用プロンプト")) {
                    Text(prompt).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(.top, 8)
                }.font(.footnote).foregroundStyle(.secondary).padding(.leading, 48)
            }
            actionSection.padding(.leading, 48)
        }
        .padding(.horizontal, 16)
        .overlay {
            if showCaptionDetail {
                captionDetailOverlay
            }
        }

    }

    @ViewBuilder
    private var detailOpenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            textSection
            imageSection
            captionSection
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard allowsDetailNavigation else { return }
            openPostDetail()
        }
    }

    // MARK: - Report submit (temporary)
    private func submitReport(_ reason: ReportReason) {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }
        let reportedPostId = post.id

        Task {
            do {
                try await ReportService.submit(
                    postId: reportedPostId,
                    reason: reason.payload(languageCode: selectedLanguage)
                )
                onPostReported?(reportedPostId)
                NotificationCenter.default.post(name: .postReported, object: nil, userInfo: ["postId": reportedPostId])
                showReportThanks = true
            } catch {
                showReportError = true
                return
            }
        }
    }

    private func deletePost() {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }

        let deletedPostId = post.id
        Task {
            do {
                let deletedPending = try await BackgroundPhotoPosts.shared.deletePendingPost(deletedPostId)
                if !deletedPending {
                    try await PostActionService.deletePost(postId: deletedPostId)
                }
                await PostStore.shared.remove(postId: deletedPostId)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .postDeleted,
                        object: nil,
                        userInfo: ["postId": deletedPostId]
                    )
                    onPostDeleted?(deletedPostId)
                }
            } catch {
                await MainActor.run {
                    showDeleteError = true
                }
            }
        }
    }
}

// MARK: - Header
extension PostCardView {
    private var headerSection: some View {
        HStack {
            Button {
                openAuthorProfileIfPossible()
            } label: {
                HStack(spacing: 12) {
                    CachedAvatarView(urlString: post.avatarUrl ?? "") {
                            avatarPlaceholder
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(post.displayName ?? l("post_card.user_fallback"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(post.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // ⋯ Menu
            Menu {
                if isCurrentUsersPost {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(l("post_card.menu.delete"), systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        showReportDialog = true
                    } label: {
                        Label(l("post_card.menu.report"), systemImage: "flag")
                    }
                }
                if shouldShowBlockAction {
                    Button(role: .destructive) {
                        showBlockConfirm = true
                    } label: {
                        Label(l("post_card.menu.block_user"), systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .tint(.secondary)
            .accessibilityLabel(mt("投稿のメニュー"))
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Color(.secondarySystemBackground)

            Text(avatarInitial)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private var avatarInitial: String {
        let base = (post.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? post.displayName!
            : l("post_card.user_fallback")
        return String(base.prefix(1)).uppercased()
    }

    private var avatarStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.5)
    }

    private var cardFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.92)
    }

    private var chromeFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }
}

extension PostCardView {
    private var shouldShowBlockAction: Bool {
        guard let postUserId = post.userId else { return false }
        return postUserId != UserManager.shared.currentUser.id
            && !BlockManager.shared.isBlocked(postUserId)
    }

    private var isCurrentUsersPost: Bool {
        guard let postUserId = post.userId else { return false }
        return postUserId == UserManager.shared.currentUser.id
    }

    private func blockAuthorIfNeeded() {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }
        guard let blockedUserId = post.userId else { return }
        Task { @MainActor in
            await BlockManager.shared.block(blockedUserId)
            onUserBlocked?(blockedUserId)
        }
    }

    private func openAuthorProfileIfPossible() {
        guard let userId = post.userId, !userId.isEmpty else { return }
        guard userId != UserManager.shared.currentUser.id else { return }
        showAuthorProfile = true
    }

    private func openPostDetail() {
        showComments = true
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}

// MARK: - Text
extension PostCardView {
    private var textSection: some View {
        Group {
            if let txt = post.userText, !txt.isEmpty {
                Text(txt)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Image section
extension PostCardView {
    @ViewBuilder
    private var imageSection: some View {
        if post.hasImage {
            if let image = post.localImage {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: MimStyle.mediaRadius))
                    .accessibilityLabel(post.caption ?? mt("投稿の画像"))
            } else {
                VStack(spacing: 12) {
                    if post.recipe == nil && (post.status == .pending || post.status == .processing) {
                        ProgressView(mt(post.localPreparationMessage ?? "写真を処理中"))
                    } else if post.recipe == nil && post.status == .failed {
                        Text(mt(post.localPreparationMessage ?? "写真を処理できませんでした。"))
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if isCurrentUsersPost {
                            Button(mt("再試行")) { BackgroundPhotoPosts.shared.retry(post.id) }
                        }
                    } else if post.imageIsGenerating {
                        ProgressView(mt("写真を再現中"))
                    } else if let reason = post.reconstructionUnavailableReason ?? post.imageGenerationFailureReason {
                        Image(systemName: "photo.badge.exclamationmark").font(.title2)
                        Text(mt(reason)).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if post.recipe != nil && post.recipeReadError == nil {
                            Button(mt("再試行")) {
                                NotificationCenter.default.post(name: .regenerateSinglePostRequested, object: post)
                            }
                        }
                    } else if !isModelInstalled {
                        Image(systemName: "photo").font(.title2)
                        Text(mt("再現モデルの準備が必要です")).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(mt("再現の準備を待っています")).font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 200).padding(16)
                    .background(MimStyle.soft, in: RoundedRectangle(cornerRadius: MimStyle.mediaRadius))
            }
        }
    }
}

// MARK: - Caption
extension PostCardView {
    @ViewBuilder
    private var captionSection: some View {
        if !isModelInstalled, post.localImage == nil, let cap = post.caption, !cap.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(cap)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if shouldShowCaptionPreviewExpansion(for: cap) {
                    Button(l("post_card.read_more")) {
                        showCaptionDetail = true
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
}

// MARK: - Like / Share
extension PostCardView {
    private var actionSection: some View {
        HStack(spacing: 24) {
            Button {
                LikeManager.shared.toggleLike(for: post)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: (post.isLikedByCurrentUser ?? false) ? "heart.fill" : "heart")
                    Text("\(post.likeCount ?? 0)")
                }
                    .foregroundColor((post.isLikedByCurrentUser ?? false) ? .red : .secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(mt("いいね"))
            .accessibilityValue("\(post.likeCount ?? 0)")

            if showsCommentButton {
                Button {
                    openPostDetail()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                        Text("\(post.commentCount ?? 0)")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
            }

            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(mt("共有"))

            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }
}

extension PostCardView {
    @ViewBuilder
    private var captionDetailOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.34 : 0.24)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    showCaptionDetail = false
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            showCaptionDetail = false
                        }
                )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(captionDetailTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        showCaptionDetail = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .padding(8)
                            .background(chromeFillColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(post.caption ?? "")
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                    }
                }
                .frame(maxHeight: 220)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 0.8)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var captionDetailTitle: String {
        mt("全文")
    }

    private func shouldShowCaptionPreviewExpansion(for caption: String) -> Bool {
        caption.count > 90 || caption.contains("\n")
    }
}

// MARK: - Share sheet
extension PostCardView {
    @ViewBuilder
    private var shareSheet: some View {
        if let img = post.localImage {
            ActivityView(activityItems: [img])
        } else if let text = post.caption {
            ActivityView(activityItems: [text])
        } else {
            ActivityView(activityItems: [l("post_card.share_fallback")])
        }
    }
}

// MARK: - Time format
extension PostCardView {
    private func relativeTimeString(from date: Date) -> String {
        ServerDate.relativeString(from: date, languageCode: selectedLanguage)
    }
}
