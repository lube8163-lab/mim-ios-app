import SwiftUI
import Combine

struct PostCardView: View {

    @ObservedObject var post: Post
    let isModelInstalled: Bool
    @EnvironmentObject private var authManager: AuthManager
    var onUserBlocked: ((String) -> Void)? = nil
    var onPostReported: ((String) -> Void)? = nil
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var showShare = false
    @State private var refreshID = UUID()

    // 🚨 Report UI states
    @State private var showReportDialog = false
    @State private var showReportThanks = false
    @State private var showReportError = false
    @State private var showBlockConfirm = false
    @State private var showLoginSheet = false

    var body: some View {
        content
            .id(refreshID)
            .onReceive(post.objectWillChange) { _ in
                refreshID = UUID()
            }
            .sheet(isPresented: $showShare) {
                shareSheet
            }
            .sheet(isPresented: $showLoginSheet) {
                OTPLoginView(allowsSkip: true)
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
            let isEnglish = languageCode.hasPrefix(AppLanguage.english.rawValue)
            switch self {
            case .inappropriate: return isEnglish ? "Inappropriate content" : "不適切な画像"
            case .violence: return isEnglish ? "Violence or gore" : "暴力・残虐"
            case .sexual: return isEnglish ? "Sexual content" : "性的コンテンツ"
            case .hate: return isEnglish ? "Hate or discrimination" : "ヘイト・差別"
            case .spam: return isEnglish ? "Spam" : "スパム"
            case .other: return isEnglish ? "Other" : "その他"
            }
        }

        func payload(languageCode: String) -> String {
            label(languageCode: languageCode)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {

            headerSection
            textSection
            imageSection
            captionSection
            actionSection

            Divider().padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
}

// MARK: - Header
extension PostCardView {
    private var headerSection: some View {
        HStack {
            AsyncImage(url: URL(string: post.avatarUrl ?? "")) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(post.displayName ?? t(ja: "ユーザー", en: "User"))
                    .font(.subheadline)
                    .bold()
                Text(post.createdAt.formatted())
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            // ⋯ Menu
            Menu {
                Button(role: .destructive) {
                    showReportDialog = true
                } label: {
                    Label(t(ja: "通報", en: "Report"), systemImage: "flag")
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
                    .padding(8)
            }
        }
        .padding(.bottom, 4)
    }
}

extension PostCardView {
    private var shouldShowBlockAction: Bool {
        guard let postUserId = post.userId else { return false }
        return postUserId != UserManager.shared.currentUser.id
            && !BlockManager.shared.isBlocked(postUserId)
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
                    .font(.body)
                    .foregroundColor(.primary)
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
                    .cornerRadius(12)
                    .transition(.opacity)
                modeBadge
            }
        }
        else if let preview = post.previewImage {
            ZStack(alignment: .topLeading) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                if isModelInstalled {
                    VStack(spacing: 6) {
                        RainbowAILoader()
                            .shadow(color: .purple.opacity(0.6), radius: 8)
                        Text(t(ja: "生成中…", en: "Generating..."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                modeBadge
            }
        }
        else if !isModelInstalled {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxHeight: 260)
                    .overlay(
                        Text(t(ja: "画像モデル未インストール", en: "Image model not installed"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
                if post.hasImage {
                    modeBadge
                }
            }
        }
        else if post.effectivePrompt != nil {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(maxHeight: 260)
                    .overlay(
                        VStack(spacing: 12) {
                            RainbowAILoader()
                                .shadow(color: .purple.opacity(0.6), radius: 8)
                            //Text("画像生成中…")
                                //.font(.caption)
                                //.foregroundColor(.secondary)
                        }
                    )
                if post.hasImage {
                    modeBadge
                }
            }
        }
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: post.privacyMode.iconName)
                .font(.caption2)
            Text(post.privacyMode.titleEN)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.58))
        .clipShape(Capsule())
        .padding(8)
    }
}

// MARK: - Caption
extension PostCardView {
    @ViewBuilder
    private var captionSection: some View {
        if let cap = post.caption {
            Text("-\(cap)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 4)
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

            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Spacer()
        }
        .font(.subheadline)
        .padding(.top, 4)
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
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
