import SwiftUI
import Combine
import UIKit

final class PostList: ObservableObject { @Published var items: [Post] = [] }

struct ContentView: View {
    enum Tab: String, CaseIterable { case home, following, posts, likes }
    enum DrawerDestination: String, Hashable { case profile, notifications, models, settings }
    private enum DetailDestination: Identifiable {
        case post(Post)
        case profile(String)

        var id: String {
            switch self {
            case .post(let post): "post:" + post.id
            case .profile(let userID): "profile:" + userID
            }
        }
    }
    private struct FeedScrollMetrics: Equatable {
        let offset: CGFloat
        let canScroll: Bool
    }
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var pushManager: PushNotificationManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var posts = PostList()
    @StateObject private var following = PostList()
    @StateObject private var mine = PostList()
    @StateObject private var liked = PostList()
    @StateObject private var blockManager = BlockManager.shared
    @ObservedObject private var photoPosts = BackgroundPhotoPosts.shared
    @State private var tab: Tab = .home
    @State private var showComposer = false
    @State private var showDrawer = false
    @State private var returnToDrawer = false
    @State private var tabBarHidden = false
    @State private var userIsScrolling = false
    @State private var lastScrollOffset: CGFloat = 0
    @State private var directionalScrollDistance: CGFloat = 0
    @State private var navigationPath: [DrawerDestination] = []
    @State private var profileStats: PublicUserProfile?
    @State private var logoutConfirmation = false
    @ObservedObject private var userManager = UserManager.shared
    @State private var loading = false
    @State private var feedError: String?
    @State private var pages: [String: Int] = [:]
    @State private var exhausted: Set<String> = []
    @State private var notifications = false
    @State private var login = false
    @State private var queue: [Post] = []
    @State private var generationTask: Task<Void, Never>?
    @State private var pausedForComposer = false
    // Cancelled task closures must observe the latest scene pause state.
    @State private var pausedForScene = true
    @State private var unreadNotificationCount = 0
    @State private var hiddenPostIDs: Set<String> = []
    @State private var selectedDetail: DetailDestination?
    @State private var destinationError: String?
    @State private var generatingPost: Post?
    @State private var refinementStatus: String?
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    private var isOfflineReview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-ui-review")
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                NavigationStack(path: $navigationPath) {
                    Group {
                        if tab == .home || authManager.isAuthenticated || isOfflineReview {
                            feedView(currentList)
                        } else {
                            ContentUnavailableView {
                                Label(mt("ログイン"), systemImage: "person.crop.circle")
                            } description: {
                                Text(mt("ログインすると投稿といいねを確認できます。"))
                            } actions: {
                                Button(mt("ログイン")) { login = true }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if tab == .home {
                            Button {
                                if authManager.isAuthenticated || isOfflineReview { showComposer = true }
                                else { login = true }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 54, height: 54)
                                    .background(MimStyle.accent, in: Circle())
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(mt("投稿する"))
                            .accessibilityIdentifier("new-post-button")
                            .padding(20)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !tabBarHidden {
                            tabBar.transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { openDrawer() } label: { avatar(size: 30) }
                                .accessibilityLabel(mt("メニュー"))
                                .accessibilityIdentifier("profile-menu-button")
                        }.sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .principal) {
                            if tab == .home {
                                Text("Mim").font(.system(.title2, design: .default).weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .accessibilityElement(children: .ignore).accessibilityLabel("Mim")
                            } else { Text(tabTitle(tab)).font(.headline) }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                if authManager.isAuthenticated || isOfflineReview { notifications = true }
                                else { login = true }
                            } label: {
                                Image(systemName: unreadNotificationCount > 0 ? "bell.badge" : "bell")
                            }.accessibilityLabel(mt("通知"))
                                .tint(.primary)
                        }.sharedBackgroundVisibility(.hidden)
                    }
                    .navigationDestination(for: DrawerDestination.self) { destination in
                        switch destination {
                        case .profile:
                            if authManager.isAuthenticated || isOfflineReview {
                                PublicProfileView(userId: isOfflineReview ? "ui-review-user" : userManager.currentUser.id,
                                                  showsCloseButton: false)
                            } else { UserProfileView(showsCloseButton: false, showAppSettings: false) }
                        case .models: ModelManagementView()
                        case .notifications:
                            NotificationsView(showsCloseButton: false) { items in
                                unreadNotificationCount = items.filter { !$0.isRead }.count
                            }
                        case .settings: SettingsView()
                        }
                    }
                }
                .accessibilityHidden(showDrawer)
                if !showDrawer && navigationPath.isEmpty {
                    Color.clear.frame(width: 28).contentShape(Rectangle())
                        .highPriorityGesture(DragGesture(minimumDistance: 18).onEnded { value in
                            if value.translation.width > 70,
                               abs(value.translation.width) > abs(value.translation.height) * 1.5 { openDrawer() }
                        })
                        .accessibilityHidden(true)
                }
                if showDrawer {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture { closeDrawer() }
                        .accessibilityLabel(mt("メニューを閉じる"))
                    drawerMenu
                        .frame(width: min(geometry.size.width * 0.82, 340))
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
            }
        }
        .tint(MimStyle.accent)
        .overlay(alignment: .top) {
            if let refinementStatus {
                Text(refinementStatus).font(.caption).padding(8).background(MimStyle.soft, in: Capsule())
                    .accessibilityIdentifier("refinement-status").allowsHitTesting(false)
            }
        }
        .task {
            #if DEBUG
            if isOfflineReview && ProcessInfo.processInfo.arguments.contains("--mim-flux-adoption-check") {
                await FluxAdoptionCheck(update: { refinementStatus = $0 }).run()
            }
            if isOfflineReview && ProcessInfo.processInfo.arguments.contains("--mim-refinement-check") {
                await DeviceRefinementCheck(update: { refinementStatus = $0 }).run()
            }
            #endif
        }
        .sheet(isPresented: $showComposer) {
            NewPostView(posts: $posts.items, onClose: { showComposer = false })
        }
        .sheet(isPresented: $notifications) {
            NotificationsView { items in unreadNotificationCount = items.filter { !$0.isRead }.count }
        }
        .sheet(isPresented: $login) { OTPLoginView(allowsSkip: true) }
        .sheet(item: $selectedDetail) { destination in
            NavigationStack {
                switch destination {
                case .post(let post):
                    PostDetailView(post: post, isModelInstalled: modelManager.canGenerateImages)
                case .profile(let userID):
                    PublicProfileView(userId: userID)
                }
            }
        }
        .alert(mt("投稿を開けませんでした"), isPresented: Binding(
            get: { destinationError != nil }, set: { if !$0 { destinationError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(mt(destinationError ?? "")) }
        .onOpenURL { url in
            if let id = PostDestination.postID(from: url) { Task { await openPost(id) } }
        }
        .onChange(of: pushManager.pendingPostID) { _, id in
            guard let id else { return }
            pushManager.pendingPostID = nil
            Task { await openPost(id) }
        }
        .onChange(of: pushManager.pendingUserID) { _, id in
            guard let id else { return }
            pushManager.pendingUserID = nil
            selectedDetail = .profile(id)
        }
        .task {
            #if DEBUG
            if isOfflineReview,
               let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--mim-ui-review-screen"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                switch ProcessInfo.processInfo.arguments[index + 1] {
                case "compose": showComposer = true
                case "settings": navigationPath = [.settings]
                case "models": navigationPath = [.models]
                case "profile": navigationPath = [.profile]
                case "notifications": notifications = true
                case "menu": openDrawer()
                case "logout": openDrawer(); logoutConfirmation = true
                default: tab = .home
                }
            }
            #endif
            if isOfflineReview { loadReviewPosts() }
            await refreshUnreadNotifications()
            if let id = pushManager.pendingPostID {
                pushManager.pendingPostID = nil
                await openPost(id)
            }
            if let id = pushManager.pendingUserID {
                pushManager.pendingUserID = nil
                selectedDetail = .profile(id)
            }
        }
        .task(id: tab) { await refresh(); await pollPendingPosts() }
        .onChange(of: tab) { _, _ in
            directionalScrollDistance = 0
            setTabBarHidden(false)
        }
        .onChange(of: navigationPath) { _, path in
            guard path.isEmpty, returnToDrawer else { return }
            returnToDrawer = false
            openDrawer()
        }
        .onChange(of: showComposer) { _, presented in
            pausedForComposer = presented
            if presented { setTabBarHidden(false) }
            if !presented { startGenerationQueue() }
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            photoPosts.accountChanged()
            photoPosts.setActive(authManager.isAuthenticated && scenePhase == .active)
            for list in [following, mine, liked] { list.items.removeAll() }
            hiddenPostIDs.removeAll()
            Task { await refresh(); await refreshUnreadNotifications() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            photoPosts.setActive(phase == .active)
            pausedForScene = phase != .active
            if phase == .active {
                modelManager.reloadState(); startGenerationQueue()
                Task { await refreshUnreadNotifications() }
            }
            else {
                generationTask?.cancel()
                Task { await RecipeImageRenderer.shared.discardFluxCache() }
            }
        }
        .onChange(of: modelManager.sdInstalled) { _, _ in retryVisible() }
        .onChange(of: modelManager.selectedSDModelID) { _, _ in retryVisible() }
        .onChange(of: photoPosts.isProcessing) { _, processing in
            if !processing { startGenerationQueue() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backgroundPhotoPostUpdated)) { notification in
            guard let post = notification.object as? Post else { return }
            if !posts.items.contains(where: { $0.id == post.id }) { posts.items.insert(post, at: 0) }
            if !mine.items.contains(where: { $0.id == post.id }) { mine.items.insert(post, at: 0) }
            enqueue([post], priority: true)
        }
        .onChange(of: language) { _, _ in }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationDidChange)) { _ in
            Task { await refreshUnreadNotifications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .generationPriorityChanged)) { notification in
            let incoming = notification.object as? [Post] ?? []
            let ids = notification.userInfo?["postIDs"] as? [String] ?? []
            enqueue(incoming, priority: true)
            let prioritized = queue.filter { ids.contains($0.id) }
            queue.removeAll { ids.contains($0.id) }
            queue.insert(contentsOf: prioritized, at: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .regenerateSinglePostRequested)) { notification in
            if let post = notification.object as? Post { retry(post, newVariation: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { notification in
            let id = notification.userInfo?["postId"] as? String ?? notification.object as? String
            if let id { removePost(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postReported)) { notification in
            if let id = notification.userInfo?["postId"] as? String { removePost(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .semanticCacheMaintenanceRequested)) { _ in
            ImageCacheManager.shared.clearAllCaches()
        }
        .onReceive(NotificationCenter.default.publisher(for: .regenerateImagesRequested)) { _ in
            for post in currentList.items where post.hasImage { retry(post, newVariation: true) }
        }
        .onDisappear { generationTask?.cancel() }
    }

    private var currentList: PostList {
        switch tab {
        case .home: return posts
        case .following: return following
        case .posts: return mine
        case .likes: return liked
        }
    }
    private var listKey: String { tab.rawValue }

    private func tabTitle(_ value: Tab) -> String {
        let key = value == .posts ? "my_posts" : value == .likes ? "liked" : value.rawValue
        return L10n.tr("content.tab." + key, languageCode: language)
    }
    private func tabIcon(_ value: Tab) -> String {
        switch value {
        case .home: return "house"
        case .following: return "person.2"
        case .posts: return "person.text.rectangle"
        case .likes: return "heart"
        }
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { value in
                Button { setTabBarHidden(false); tab = value } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabIcon(value)).font(.body.weight(.medium))
                        Text(tabTitle(value)).font(.caption2)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .foregroundStyle(tab == value ? MimStyle.accent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == value ? .isSelected : [])
                .accessibilityIdentifier("feed-tab-" + value.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(MimStyle.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { MimStyle.line.frame(height: 0.5) }
    }

    private func avatar(size: CGFloat) -> some View {
        CachedAvatarView(urlString: userManager.currentUser.avatarUrl) {
            Circle().fill(Color(.secondarySystemBackground))
                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    private func openDrawer() {
        setTabBarHidden(false)
        withAnimation(.easeOut(duration: 0.22)) { showDrawer = true }
    }
    private func closeDrawer() { withAnimation(.easeOut(duration: 0.22)) { showDrawer = false } }
    private var drawerMenu: some View {
        NavigationStack {
            GeometryReader { drawerGeometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            avatar(size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(userManager.currentUser.displayName).font(.title2.weight(.semibold))
                                if !userManager.currentUser.bio.isEmpty {
                                    Text(userManager.currentUser.bio).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            if let profileStats {
                                HStack(spacing: 20) {
                                    Text("\(profileStats.followingCount) " + L10n.tr("content.drawer.following", languageCode: language))
                                    Text("\(profileStats.followerCount) " + L10n.tr("content.drawer.followers", languageCode: language))
                                }.font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        VStack(spacing: 0) {
                            drawerLink(.profile, title: "プロフィール", icon: "person")
                            drawerAction(title: "通知", icon: unreadNotificationCount > 0 ? "bell.badge" : "bell", id: "drawer-notifications") {
                                if authManager.isAuthenticated || isOfflineReview { navigateFromDrawer(to: .notifications) }
                                else { closeDrawer(); login = true }
                            }
                            drawerLink(.models, title: "モデル管理", icon: "cpu")
                        }
                        Divider()
                        VStack(spacing: 0) {
                            drawerLink(.settings, title: "設定", icon: "gearshape")
                            drawerAction(title: authManager.isAuthenticated || isOfflineReview ? "ログアウト" : "ログイン",
                                         icon: "rectangle.portrait.and.arrow.right", id: "drawer-session") {
                                if authManager.isAuthenticated || isOfflineReview { logoutConfirmation = true }
                                else { closeDrawer(); login = true }
                            }
                        }
                    }.padding(20)
                    .frame(maxWidth: .infinity, minHeight: drawerGeometry.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        closeDrawerIfSwiped(value)
                    })
                }
                .accessibilityIdentifier("profile-drawer")
            }
            .background(MimStyle.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { closeDrawer() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(mt("メニューを閉じる"))
                }
            }
            .task {
                guard authManager.isAuthenticated, !isOfflineReview else { return }
                profileStats = try? await FollowService.fetchPublicProfile(userId: userManager.currentUser.id)
            }
        }
        .mimLogoutConfirmation(isPresented: $logoutConfirmation) {
            returnToDrawer = false
            closeDrawer()
            Task { await authManager.logout() }
        }
    }
    private func drawerLink(_ destination: DrawerDestination, title: String, icon: String) -> some View {
        drawerAction(title: title, icon: icon, id: "drawer-" + destination.rawValue) { navigateFromDrawer(to: destination) }
    }
    private func navigateFromDrawer(to destination: DrawerDestination) {
        returnToDrawer = true
        closeDrawer()
        navigationPath.append(destination)
    }
    private func drawerAction(title: String, icon: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { drawerRow(title, icon: icon) }
            .buttonStyle(.plain)
            .highPriorityGesture(DragGesture(minimumDistance: 10)
                .onEnded { closeDrawerIfSwiped($0) })
            .accessibilityLabel(mt(title))
            .accessibilityIdentifier(id)
    }
    private func closeDrawerIfSwiped(_ value: DragGesture.Value) {
        if value.translation.width < -70,
           abs(value.translation.width) > abs(value.translation.height) * 1.5 { closeDrawer() }
    }
    private func drawerRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.body).frame(width: 24)
            Text(mt(title)).font(.body)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
    private func loadReviewPosts() {
        #if DEBUG
        posts.items = UIReviewFixtures.posts()
        following.items = Array(posts.items.prefix(1))
        mine.items = Array(posts.items.suffix(1))
        liked.items = Array(posts.items.prefix(1))
        exhausted = Set(Tab.allCases.map(\.rawValue))
        #endif
    }
    private func feedView(_ list: PostList) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let feedError {
                    VStack(spacing: 8) {
                        Text(mt(feedError)).foregroundStyle(.secondary)
                        Button(mt("再試行")) { Task { await refresh() } }
                    }.padding()
                }
                if loading && list.items.isEmpty { ProgressView().padding(40) }
                if !loading && list.items.isEmpty {
                    ContentUnavailableView(mt("まだ投稿がありません"), systemImage: "photo.on.rectangle")
                }
                ForEach(blockManager.filterBlocked(from: list.items).filter { !hiddenPostIDs.contains($0.id) }) { post in
                    PostCardView(post: post, isModelInstalled: modelManager.canGenerateImages,
                                 priorityContextPostIDs: list.items.map(\.id),
                                 onUserBlocked: { _ in queue = blockManager.filterBlocked(from: queue) },
                                 onPostReported: removePost, onPostDeleted: removePost)
                        .padding(.vertical, 16)
                        .onAppear { enqueue([post]) }
                    MimStyle.line.frame(height: 0.5)
                }
                if !exhausted.contains(listKey), !list.items.isEmpty {
                    Button(mt("さらに読み込む")) { Task { await loadNext() } }.disabled(loading).padding(20)
                }
            }
        }
        .accessibilityIdentifier("feed-scroll-view")
        .onScrollPhaseChange { _, phase in
            userIsScrolling = phase == .interacting || phase == .decelerating
            if phase == .tracking || phase == .idle { directionalScrollDistance = 0 }
        }
        .onScrollGeometryChange(for: FeedScrollMetrics.self) { geometry in
            let maximum = max(0, geometry.contentSize.height - geometry.containerSize.height
                + geometry.contentInsets.top + geometry.contentInsets.bottom)
            return FeedScrollMetrics(offset: min(maximum, max(0, geometry.contentOffset.y + geometry.contentInsets.top)),
                                     canScroll: maximum > 100)
        } action: { _, metrics in
            updateTabBar(for: metrics)
        }
        .refreshable { await refresh() }.background(MimStyle.paper)
    }
    private func setTabBarHidden(_ hidden: Bool) {
        guard tabBarHidden != hidden else { return }
        withAnimation(.easeInOut(duration: 0.18)) { tabBarHidden = hidden }
    }
    private func updateTabBar(for metrics: FeedScrollMetrics) {
        defer { lastScrollOffset = metrics.offset }
        guard metrics.canScroll, metrics.offset > 24 else {
            directionalScrollDistance = 0
            setTabBarHidden(false)
            return
        }
        guard userIsScrolling, !showDrawer, navigationPath.isEmpty else { return }
        let delta = metrics.offset - lastScrollOffset
        guard abs(delta) > 0.5 else { return }
        if delta * directionalScrollDistance < 0 { directionalScrollDistance = delta }
        else { directionalScrollDistance += delta }
        if directionalScrollDistance > 36, metrics.offset > 80 { setTabBarHidden(true) }
        else if directionalScrollDistance < -20 { setTabBarHidden(false) }
    }

    private func fetch(page: Int) async throws -> [Post] {
        switch tab {
        case .home: return try await FeedLoader.fetchPage(page: page)
        case .following:
            guard authManager.isAuthenticated else { return [] }
            return try await FeedLoader.fetchFollowingFeed(page: page)
        case .posts:
            guard authManager.isAuthenticated else { return [] }
            return try await FeedLoader.fetchMyPosts(userId: userManager.currentUser.id, page: page)
        case .likes:
            guard authManager.isAuthenticated else { return [] }
            return try await FeedLoader.fetchLikedPosts(userId: userManager.currentUser.id, page: page)
        }
    }
    private func refresh() async {
        guard !loading else { return }
        if isOfflineReview { return }
        let list = currentList; let key = listKey
        loading = true; feedError = nil
        defer { loading = false }
        do {
            let received = try await fetch(page: 0)
            let local = (tab == .home || tab == .posts) && authManager.isAuthenticated ? await photoPosts.localPosts() : []
            let receivedIDs = Set(received.map(\.id))
            list.items = (local.filter { !receivedIDs.contains($0.id) } + received).filter { !hiddenPostIDs.contains($0.id) }
            pages[key] = 0
            if received.count < 10 { exhausted.insert(key) } else { exhausted.remove(key) }
            enqueue(received)
        } catch { feedError = "投稿を読み込めませんでした。再試行してください。" }
    }
    private func loadNext() async {
        guard !loading, !isOfflineReview else { return }
        let list = currentList; let key = listKey
        let next = (pages[key] ?? 0) + 1
        loading = true
        defer { loading = false }
        do {
            let received = try await fetch(page: next)
            let existing = Set(list.items.map(\.id))
            list.items += received.filter { !existing.contains($0.id) && !hiddenPostIDs.contains($0.id) }
            pages[key] = next
            if received.count < 10 { exhausted.insert(key) }
            enqueue(received)
        } catch { feedError = "追加の投稿を読み込めませんでした。" }
    }
    private func pollPendingPosts() async {
        guard !isOfflineReview else { return }
        for _ in 0..<24 {
            let pending = currentList.items.filter { $0.hasImage && $0.recipe == nil && ($0.status == .pending || $0.status == .processing) }
            guard !pending.isEmpty, !Task.isCancelled else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard scenePhase == .active else { return }
            for post in pending.prefix(10) {
                if let updated = try? await FeedLoader.fetchPost(id: post.id) { enqueue([updated]) }
            }
        }
    }
    private func enqueue(_ incoming: [Post], priority: Bool = false) {
        let candidates = blockManager.filterBlocked(from: incoming).filter { post in
            guard post.hasImage, post.recipe != nil, post.recipeReadError == nil,
                  post.localImage == nil, !post.imageGenerationFailed, !post.imageIsGenerating,
                  !hiddenPostIDs.contains(post.id) else { return false }
            return !queue.contains { $0.id == post.id }
        }
        if priority { queue.insert(contentsOf: candidates, at: 0) } else { queue.append(contentsOf: candidates) }
        startGenerationQueue()
    }
    private func startGenerationQueue() {
        guard generationTask == nil, !pausedForComposer, !pausedForScene,
              !photoPosts.isProcessing, scenePhase == .active, !isOfflineReview else { return }
        generationTask = Task {
            defer {
                generationTask = nil
                if !queue.isEmpty { startGenerationQueue() }
            }
            while !queue.isEmpty && !Task.isCancelled && !pausedForComposer && !pausedForScene && scenePhase == .active {
                let post = queue.removeFirst()
                guard let recipe = post.recipe, !hiddenPostIDs.contains(post.id) else { continue }
                generatingPost = post
                defer { post.imageIsGenerating = false; generatingPost = nil }
                do {
                    try recipe.validate()
                    let seed = try ViewerSeedStore.shared.seed(for: recipe, postID: post.id)
                    let key = try recipe.renderCacheKey(seed: seed)
                    let installed = try await modelManager.manifest(for: recipe.model.modelID)
                    try recipe.validate(installedManifest: installed)
                    if let cached = try await ImageCacheManager.shared.load(for: key) {
                        post.localImage = cached; post.localImageRecipeKey = key
                        continue
                    }
                    post.imageIsGenerating = true
                    let image = try await RecipeImageRenderer.shared.render(recipe, seed: seed)
                    try Task.checkCancellation()
                    guard post.recipe == recipe,
                          seed == (try ViewerSeedStore.shared.seed(for: recipe, postID: post.id)) else { continue }
                    post.localImage = image; post.localImageRecipeKey = key
                    ImageCacheManager.shared.save(image, for: key)
                } catch is CancellationError {
                    if !hiddenPostIDs.contains(post.id) { queue.insert(post, at: 0) }
                } catch {
                    post.imageGenerationFailed = true
                    post.imageGenerationFailureReason = error.localizedDescription
                }
            }
        }
    }
    private func retry(_ post: Post, newVariation: Bool = false) {
        if let recipe = post.recipe, let seed = try? ViewerSeedStore.shared.seed(for: recipe, postID: post.id),
           let key = try? recipe.renderCacheKey(seed: seed) {
            ImageCacheManager.shared.remove(for: key)
            if newVariation { _ = try? ViewerSeedStore.shared.seed(for: recipe, postID: post.id, replacing: true) }
        }
        if generatingPost?.id == post.id { generationTask?.cancel() }
        post.imageGenerationFailed = false; post.imageGenerationFailureReason = nil
        post.localImage = nil; post.localImageRecipeKey = nil
        enqueue([post], priority: true)
    }
    private func retryVisible() { for post in currentList.items where post.localImage == nil { retry(post) } }
    private func removePost(_ id: String) {
        hiddenPostIDs.insert(id)
        photoPosts.remove(id)
        for list in [posts, following, mine, liked] { list.items.removeAll { $0.id == id } }
        queue.removeAll { $0.id == id }
        if generatingPost?.id == id { generationTask?.cancel() }
        if case .post(let post) = selectedDetail, post.id == id { selectedDetail = nil }
        Task { await PostStore.shared.remove(postId: id) }
    }
    private func refreshUnreadNotifications() async {
        guard authManager.isAuthenticated, !isOfflineReview else { unreadNotificationCount = 0; return }
        if let items = try? await NotificationService.fetchNotifications(limit: 30) {
            unreadNotificationCount = items.filter { !$0.isRead }.count
        }
    }
    private func openPost(_ id: String) async {
        guard !isOfflineReview, !hiddenPostIDs.contains(id) else { return }
        do {
            let post = try await FeedLoader.fetchPost(id: id)
            guard !hiddenPostIDs.contains(post.id), !blockManager.filterBlocked(from: [post]).isEmpty else { return }
            tab = .home
            selectedDetail = .post(post)
            enqueue([post], priority: true)
        } catch { destinationError = "投稿を開けませんでした。再試行してください。" }
    }
}
