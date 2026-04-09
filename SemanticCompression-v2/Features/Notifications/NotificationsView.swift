import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    let onNotificationsLoaded: ([AppNotification]) -> Void

    @State private var items: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPost: Post?
    @State private var selectedProfileUserID: String?
    @State private var isOpeningDestination = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && isLoading {
                    ProgressView(l("notifications.loading"))
                } else if items.isEmpty {
                    emptyView
                } else {
                    List(items) { item in
                        NotificationRow(item: item, languageCode: selectedLanguage) {
                            Task { await openDestination(for: item) }
                        }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(l("notifications.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l("notifications.close")) { dismiss() }
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
            .overlay {
                if isOpeningDestination {
                    ProgressView()
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .sheet(item: $selectedPost) { post in
                NavigationStack {
                    PostDetailView(post: post, isModelInstalled: ModelManager.shared.canGenerateImages)
                }
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
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(l("notifications.empty.title"))
                .font(.headline)
            Text(l("notifications.empty.message"))
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
            errorMessage = l("notifications.error.load_failed")
        }
    }

    @MainActor
    private func openDestination(for item: AppNotification) async {
        isOpeningDestination = true
        defer { isOpeningDestination = false }

        do {
            switch item.type {
            case .follow:
                selectedProfileUserID = item.actorUserId
            case .like, .comment:
                guard let postId = item.postId else { return }
                selectedPost = try await FeedLoader.fetchPost(id: postId)
            }
        } catch {
            errorMessage = l("notifications.error.open_failed")
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}

private struct NotificationRow: View {
    let item: AppNotification
    let languageCode: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
                        .multilineTextAlignment(.leading)
                    Text(relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

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
        .buttonStyle(.plain)
    }

    private var message: String {
        let actor = item.actorDisplayName ?? L10n.tr("notifications.actor.someone", languageCode: languageCode)
        switch item.type {
        case .like:
            return L10n.tr("notifications.message.like", languageCode: languageCode, fallback: nil, actor)
        case .comment:
            return L10n.tr("notifications.message.comment", languageCode: languageCode, fallback: nil, actor)
        case .follow:
            return L10n.tr("notifications.message.follow", languageCode: languageCode, fallback: nil, actor)
        }
    }

    private var relativeTime: String {
        ServerDate.relativeString(from: item.createdAt, languageCode: languageCode)
    }
}
