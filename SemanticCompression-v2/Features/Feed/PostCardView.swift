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
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.proModeEnabledKey)
    private var isProModeEnabled = false

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
            .sheet(isPresented: $showCaptionDetail) {
                captionDetailSheet
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
                t(ja: "この投稿を通報しますか？", en: "Report this post?"),
                isPresented: $showReportDialog,
                titleVisibility: .visible
            ) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.label(languageCode: selectedLanguage), role: .destructive) {
                        submitReport(reason)
                    }
                }
                Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
            }
            .alert(t(ja: "通報を受け付けました", en: "Report submitted"), isPresented: $showReportThanks) {
                Button("OK") {}
            } message: {
                Text(t(ja: "内容を確認の上、必要に応じて対応します。", en: "We will review the report and take appropriate action if needed."))
            }
            .alert(
                t(ja: "通報に失敗しました", en: "Report failed"),
                isPresented: $showReportError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(t(ja: "時間をおいて再度お試しください。", en: "Please try again later."))
            }
            .confirmationDialog(
                t(ja: "このユーザーをブロックしますか？", en: "Block this user?"),
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(t(ja: "ブロックする", en: "Block"), role: .destructive) {
                    blockAuthorIfNeeded()
                }
                Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                t(ja: "この投稿を削除しますか？", en: "Delete this post?"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(t(ja: "削除する", en: "Delete"), role: .destructive) {
                    deletePost()
                }
                Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
            }
            .alert(
                t(ja: "投稿を削除できませんでした", en: "Failed to delete post"),
                isPresented: $showDeleteError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(t(ja: "時間をおいて再度お試しください。", en: "Please try again later."))
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
                return localizedText(languageCode: languageCode, ja: "不適切な画像", en: "Inappropriate content")
            case .violence:
                return localizedText(languageCode: languageCode, ja: "暴力・残虐", en: "Violence or gore")
            case .sexual:
                return localizedText(languageCode: languageCode, ja: "性的コンテンツ", en: "Sexual content")
            case .hate:
                return localizedText(languageCode: languageCode, ja: "ヘイト・差別", en: "Hate or discrimination")
            case .spam:
                return localizedText(languageCode: languageCode, ja: "スパム", en: "Spam")
            case .other:
                return localizedText(languageCode: languageCode, ja: "その他", en: "Other")
            }
        }

        func payload(languageCode: String) -> String {
            label(languageCode: languageCode)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            detailOpenSection
            actionSection
            semanticFidelitySection
        }
        .padding(16)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05), radius: 10, y: 4)
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
            } catch {
                showReportError = true
                return
            }
        }
        onPostReported?(reportedPostId)
        showReportThanks = true
    }

    private func deletePost() {
        guard authManager.isAuthenticated else {
            showLoginSheet = true
            return
        }

        let deletedPostId = post.id
        Task {
            do {
                try await PostActionService.deletePost(postId: deletedPostId)
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
                    AsyncImage(url: URL(string: post.avatarUrl ?? "")) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(avatarStrokeColor, lineWidth: 1))

                    VStack(alignment: .leading) {
                        Text(post.displayName ?? t(ja: "ユーザー", en: "User"))
                            .font(.subheadline.weight(.semibold))
                        Text(post.createdAt.formatted())
                            .font(.caption2)
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
                        Label(t(ja: "削除", en: "Delete"), systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        showReportDialog = true
                    } label: {
                        Label(t(ja: "通報", en: "Report"), systemImage: "flag")
                    }
                }
                if shouldShowBlockAction {
                    Button(role: .destructive) {
                        showBlockConfirm = true
                    } label: {
                        Label(t(ja: "このユーザーをブロック", en: "Block User"), systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .padding(10)
                    .background(chromeFillColor, in: Circle())
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.gray.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    Color.gray.opacity(colorScheme == .dark ? 0.14 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(avatarInitial)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private var avatarInitial: String {
        let base = (post.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? post.displayName!
            : t(ja: "ユーザー", en: "User")
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

    @ViewBuilder
    private var semanticFidelitySection: some View {
        if isCurrentUsersPost, let evaluation = post.regenerationEvaluation {
            VStack(alignment: .leading, spacing: 4) {
                if let score = evaluation.score {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption2)
                        Text(
                            t(
                                ja: "意味保持率 \(Int((score * 100).rounded()))%",
                                en: "Semantic fidelity \(Int((score * 100).rounded()))%"
                            )
                        )
                        .font(.caption2.weight(.semibold))
                    }
                }

                if isProModeEnabled {
                    if let promptLine = diagnosticLine(
                        labelJA: "Prompt",
                        labelEN: "Prompt",
                        duration: evaluation.promptGenerationDuration,
                        memoryMB: evaluation.promptGenerationMemoryMB
                    ) {
                        Text(promptLine)
                            .font(.caption2)
                    }

                    if let imageLine = diagnosticLine(
                        labelJA: "生成",
                        labelEN: "Image",
                        duration: evaluation.imageGenerationDuration,
                        memoryMB: evaluation.imageGenerationMemoryMB
                    ) {
                        Text(imageLine)
                            .font(.caption2)
                    }
                }
            }
            .foregroundColor(.secondary)
        }
    }

    private var isCurrentUsersPost: Bool {
        guard let postUserId = post.userId else { return false }
        return postUserId == UserManager.shared.currentUser.id
    }

    private func diagnosticLine(
        labelJA: String,
        labelEN: String,
        duration: TimeInterval?,
        memoryMB: Double?
    ) -> String? {
        guard duration != nil || memoryMB != nil else { return nil }

        let durationText = duration.map { String(format: "%.1fs", $0) } ?? "-"
        let memoryText = memoryMB.map { formatMemory($0) } ?? "-"
        return t(
            ja: "\(labelJA) \(durationText) / \(memoryText)",
            en: "\(labelEN) \(durationText) / \(memoryText)"
        )
    }

    private func formatMemory(_ valueMB: Double) -> String {
        if valueMB >= 1024 {
            return String(format: "%.2f GB", valueMB / 1024)
        }
        return String(format: "%.0f MB", valueMB)
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

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}

// MARK: - Text
extension PostCardView {
    private var textSection: some View {
        Group {
            if let txt = post.userText, !txt.isEmpty {
                Text(txt)
                    .font(.body.weight(.medium))
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
        if let img = post.localImage {
            ZStack(alignment: .topLeading) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .transition(.opacity)
                imageBadges
            }
        }
        else if let preview = post.previewImage {
            ZStack(alignment: .topLeading) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                if isModelInstalled {
                    VStack(spacing: 6) {
                        RainbowAILoader()
                            .shadow(color: .purple.opacity(0.6), radius: 8)
                        Text(t(ja: "生成中…", en: "Generating..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 28)
                    .padding(.leading, 72)
                    .padding(.trailing, 16)
                }
                imageBadges
            }
        }
        else if !isModelInstalled {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxHeight: 260)
                    .overlay(
                        Text(t(ja: "画像生成を利用できません", en: "Image generation unavailable"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
                if post.hasImage {
                    imageBadges
                }
            }
        }
        else if post.effectivePrompt != nil {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(minHeight: post.imageGenerationFailed ? 170 : nil, maxHeight: 260)
                    .overlay(
                        Group {
                            if post.imageGenerationFailed {
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                    if let reason = post.imageGenerationFailureReason {
                                        Text(reason)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }
                                    if post.imageGenerationFailureReason == nil {
                                        Text(t(ja: "もう一度お試しください。", en: "Please try again."))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.top, 26)
                                .padding(.leading, 76)
                                .padding(.trailing, 20)
                                .padding(.bottom, 18)
                            } else {
                                VStack(spacing: 12) {
                                    RainbowAILoader()
                                        .shadow(color: .purple.opacity(0.6), radius: 8)
                                    Text(t(ja: "生成中…", en: "Generating..."))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 28)
                                .padding(.leading, 72)
                                .padding(.trailing, 16)
                            }
                        }
                    )
                if post.hasImage {
                    imageBadges
                }
            }
        }
    }

    private var imageBadges: some View {
        VStack(alignment: .leading, spacing: 6) {
            modeBadge
            if let generationStatusLabel {
                HStack(spacing: 4) {
                    Image(systemName: generationStatusIconName)
                        .font(.caption2)
                    Text(generationStatusLabel)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.58))
                .clipShape(Capsule())
            }
        }
        .padding(8)
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: post.privacyMode.iconName)
                .font(.caption2)
            Text(post.privacyMode.title(languageCode: selectedLanguage))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.58))
        .clipShape(Capsule())
    }

    private var generationStatusLabel: String? {
        if post.imageGenerationFailed {
            return t(ja: "失敗", en: "Failed")
        }
        if post.status == .failed {
            return t(ja: "失敗", en: "Failed")
        }
        if post.localImage != nil {
            return nil
        }
        if post.effectivePrompt != nil {
            return t(ja: "再生成待ち", en: "Queued")
        }
        if post.hasImage && (post.status == .pending || post.status == .processing) {
            return t(ja: "準備中", en: "Preparing")
        }
        return nil
    }

    private var generationStatusIconName: String {
        if post.imageGenerationFailed {
            return "exclamationmark.triangle.fill"
        }
        if post.status == .failed {
            return "exclamationmark.triangle.fill"
        }
        if post.effectivePrompt != nil {
            return "clock.arrow.circlepath"
        }
        return "sparkles"
    }
}

// MARK: - Caption
extension PostCardView {
    @ViewBuilder
    private var captionSection: some View {
        if let cap = post.caption {
            VStack(alignment: .leading, spacing: 6) {
                Text("-\(cap)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)

                if let backend = post.imageUnderstandingBackendLabel, post.hasImage {
                    Text(t(ja: "画像理解: \(backend)", en: "Image understanding: \(backend)"))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                if cap.count > 140 {
                    Button(t(ja: "続きを読む", en: "Read more")) {
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
            HStack(spacing: 6) {
                Button {
                    LikeManager.shared.toggleLike(for: post)
                } label: {
                    Image(systemName: (post.isLikedByCurrentUser ?? false) ? "heart.fill" : "heart")
                        .foregroundColor((post.isLikedByCurrentUser ?? false) ? .red : .primary)
                }

                Text("\(post.likeCount ?? 0)")
                    .font(.subheadline)
                    .foregroundColor((post.isLikedByCurrentUser ?? false) ? .red : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chromeFillColor, in: Capsule())

            if showsCommentButton {
                Button {
                    openPostDetail()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                        Text("\(post.commentCount ?? 0)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(chromeFillColor, in: Capsule())
            }

            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chromeFillColor, in: Capsule())

            Spacer()
        }
        .font(.subheadline)
        .padding(.top, 4)
    }
}

extension PostCardView {
    @ViewBuilder
    private var captionDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(post.caption ?? "")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if let backend = post.imageUnderstandingBackendLabel, post.hasImage {
                        Text(t(ja: "この投稿の画像理解: \(backend)", en: "Image understanding for this post: \(backend)"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle(t(ja: "キャプション全文", en: "Full Caption"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t(ja: "閉じる", en: "Close")) {
                        showCaptionDetail = false
                    }
                }
            }
        }
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
            ActivityView(activityItems: [t(ja: "この投稿をチェックしてみてください！", en: "Check out this post on SemanticCompression!")])
        }
    }
}

// MARK: - Time format
extension PostCardView {
    private func relativeTimeString(from date: Date) -> String {
        ServerDate.relativeString(from: date, languageCode: selectedLanguage)
    }
}
