import SwiftUI
import Combine

struct PostCardView: View {

    @ObservedObject var post: Post
    let isModelInstalled: Bool
    var onUserBlocked: ((String) -> Void)? = nil
    var onPostReported: ((String) -> Void)? = nil
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var showShare = false
    @State private var refreshID = UUID()

    // 🚨 Report UI states
    @State private var showReportDialog = false
    @State private var showReportThanks = false
    @State private var showBlockConfirm = false

    var body: some View {
        content
            .id(refreshID)
            .onReceive(post.objectWillChange) { _ in
                refreshID = UUID()
            }
            .sheet(isPresented: $showShare) {
                shareSheet
            }
            .confirmationDialog(
                "この投稿を通報しますか？",
                isPresented: $showReportDialog,
                titleVisibility: .visible
            ) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.rawValue, role: .destructive) {
                        submitReport(reason)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .alert("通報を受け付けました", isPresented: $showReportThanks) {
                Button("OK") {}
            } message: {
                Text("内容を確認の上、必要に応じて対応します。")
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
        let userId = UserManager.shared.currentUser.id   // ← ここ重要
        let reportedPostId = post.id

        Task {
            await ReportService.submit(
                postId: reportedPostId,
                reason: reason.rawValue,
                reporterUserId: userId
            )
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
                Text(post.displayName ?? "User")
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
                    Label("通報", systemImage: "flag")
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
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .transition(.opacity)
        }
        else if !isModelInstalled {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
                .frame(maxHeight: 260)
                .overlay(
                    Text("画像モデル未インストール")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        }
        else if post.semanticPrompt != nil {
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
        }
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
            ActivityView(activityItems: ["Check out this post on SemanticCompression!"])
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
