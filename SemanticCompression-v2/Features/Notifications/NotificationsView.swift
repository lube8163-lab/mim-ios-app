import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    let onNotificationsLoaded: ([AppNotification]) -> Void

    @State private var items: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && isLoading {
                    ProgressView(t(ja: "通知を読み込み中...", en: "Loading notifications...", zh: "正在加载通知..."))
                } else if items.isEmpty {
                    emptyView
                } else {
                    List(items) { item in
                        NotificationRow(item: item, languageCode: selectedLanguage)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(t(ja: "通知", en: "Notifications", zh: "通知"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t(ja: "閉じる", en: "Close", zh: "关闭")) { dismiss() }
                }
            }
            .task {
                await loadNotifications()
            }
            .refreshable {
                await loadNotifications()
            }
            .overlay(alignment: .top) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(t(ja: "通知はまだありません", en: "No notifications yet", zh: "还没有通知"))
                .font(.headline)
            Text(t(ja: "いいね、コメント、フォローが来るとここに表示されます。", en: "Likes, comments, and follows will appear here.", zh: "点赞、评论和关注会显示在这里。"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @MainActor
    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let notifications = try await NotificationService.fetchNotifications()
            items = notifications
            onNotificationsLoaded(notifications)
            try await NotificationService.markAllAsRead()
            PushNotificationManager.shared.clearBadges()
            let readItems = notifications.map { item in
                AppNotification(
                    id: item.id,
                    type: item.type,
                    actorUserId: item.actorUserId,
                    actorDisplayName: item.actorDisplayName,
                    actorAvatarUrl: item.actorAvatarUrl,
                    postId: item.postId,
                    commentId: item.commentId,
                    createdAt: item.createdAt,
                    isRead: true
                )
            }
            items = readItems
            onNotificationsLoaded(readItems)
            PushNotificationManager.shared.setBadgeCount(0)
            errorMessage = nil
        } catch {
            errorMessage = t(ja: "通知の読み込みに失敗しました", en: "Failed to load notifications", zh: "加载通知失败")
        }
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}

private struct NotificationRow: View {
    let item: AppNotification
    let languageCode: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: item.actorAvatarUrl ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(Color.secondary.opacity(0.14))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .font(.subheadline)
                Text(relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !item.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var message: String {
        let actor = item.actorDisplayName ?? localizedText(languageCode: languageCode, ja: "誰か", en: "Someone", zh: "某人")
        switch item.type {
        case .like:
            return localizedText(languageCode: languageCode, ja: "\(actor) があなたの投稿にいいねしました", en: "\(actor) liked your post", zh: "\(actor) 赞了你的帖子")
        case .comment:
            return localizedText(languageCode: languageCode, ja: "\(actor) があなたの投稿にコメントしました", en: "\(actor) commented on your post", zh: "\(actor) 评论了你的帖子")
        case .follow:
            return localizedText(languageCode: languageCode, ja: "\(actor) があなたをフォローしました", en: "\(actor) followed you", zh: "\(actor) 关注了你")
        }
    }

    private var relativeTime: String {
        ServerDate.relativeString(from: item.createdAt, languageCode: languageCode)
    }
}
