import SwiftUI
import Combine
import CoreML

final class PostList: ObservableObject {
    @Published var items: [Post] = []
}

struct ContentView: View {

    // MARK: - Boot State

    enum AppBootState {
        case launching
        case preparingModel
        case ready
    }

    enum HomeTab {
        case timeline
        case following
        case myPosts
        case liked
    }

    @State private var appBootState: AppBootState = .launching

    // MARK: - Core State

    @StateObject private var postList = PostList()
    @StateObject private var followingPostList = PostList()
    @StateObject private var myPostList = PostList()
    @StateObject private var likedPostList = PostList()
    @StateObject private var blockManager = BlockManager.shared
    @StateObject private var userManager = UserManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject var modelManager: ModelManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var showNewPost = false
    @State private var showInstallModels = false
    @State private var selectedTab: HomeTab = .timeline

    @State private var genLog = "Ready"
    @State private var isLoadingFeed = false
    @State private var isLoadingFollowingFeed = false
    @State private var isLoadingMyPosts = false
    @State private var isLoadingLikedPosts = false

    @State private var generator: ImageGenerator?
    @State private var isGeneratorReady = false
    @State private var loadedSDModelID: String?

    // Pagination
    @State private var currentPage = 0
    @State private var currentFollowingPage = 0
    @State private var currentMyPage = 0
    @State private var currentLikedPage = 0
    private let pageSize = 10
    @State private var hasLoadedFollowingFeed = false
    @State private var hasLoadedMyPosts = false
    @State private var hasLoadedLikedPosts = false

    // Image generation queue
    @State private var generationQueue: [Post] = []
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var isGenerationSuspendedForPosting = false
    @State private var showReportToast = false
    @State private var showBlockToast = false
    @State private var showLoginSheet = false
    @State private var showProfileDrawer = false
    @State private var showNotifications = false
    @State private var showRegenerateConfirm = false
    @State private var semanticScoreTasks: Set<String> = []
    @State private var unreadNotificationCount = 0
    @State private var profileDrawerDragTranslation: CGFloat = 0
    @State private var isChromeHidden = false
    @State private var currentProfileStats: PublicUserProfile?
    @State private var externallyPrioritizedPostIDs: [String] = []

    // MARK: - Body

    var body: some View {
        ZStack {
            switch appBootState {
            case .launching, .preparingModel:
                AppLaunchView()

            case .ready:
                mainContent
            }
        }
        .task {
            await bootSequence()
        }
        .onChange(of: selectedLanguage) { _ in
            localizeGenLogIfNeeded()
        }
        .onChange(of: modelManager.selectedSDModelID) { _ in
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
        .onChange(of: modelManager.sdInstalled) { installed in
            guard installed else { return }
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
        .onChange(of: showInstallModels) { shown in
            guard !shown else { return }
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task {
                await maybeReloadGeneratorForSelectedModel()
                await refreshUnreadNotificationsIfNeeded()
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, authenticated in
            Task { await handleAuthenticationChange(isAuthenticated: authenticated) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .semanticCacheMaintenanceRequested)) { _ in
            Task { await clearAllImageCachesAndRegenerate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .regenerateImagesRequested)) { _ in
            showRegenerateConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .generationPriorityChanged)) { notification in
            let ids = notification.userInfo?["postIDs"] as? [String] ?? []
            externallyPrioritizedPostIDs = ids
            let prioritizedPosts = notification.object as? [Post] ?? []
            prioritizeGenerationForCurrentContext(using: prioritizedPosts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .regenerateSinglePostRequested)) { notification in
            guard let postID = notification.userInfo?["postID"] as? String else { return }
            let post = notification.object as? Post
            Task { await regenerateImage(for: postID, post: post) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationDidChange)) { _ in
            Task { await refreshUnreadNotificationsIfNeeded(force: true) }
        }
        .onChange(of: selectedTab) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                isChromeHidden = false
            }
            prioritizeGenerationForCurrentContext()
        }
        .onChange(of: showProfileDrawer) { shown in
            if shown {
                Task { await refreshCurrentProfileStats() }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showReportToast {
                    Text(t(ja: "通報を受け付けました。投稿を非表示にしました。", en: "Report submitted. The post was hidden.", zh: "举报已提交，帖子已被隐藏。"))
                        .toastStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showBlockToast {
                    Text(t(ja: "ユーザーをブロックしました。投稿を非表示にしました。", en: "User blocked. Posts were hidden.", zh: "用户已被屏蔽，相关帖子已隐藏。"))
                        .toastStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: showReportToast)
        .animation(.easeInOut(duration: 0.2), value: showBlockToast)
        .overlay {
            if appBootState == .ready {
                profileDrawerOverlay
            }
        }
        .overlay(alignment: .leading) {
            if appBootState == .ready && !showProfileDrawer {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(profileDrawerEdgeGesture)
            }
        }
        .alert(
            t(
                ja: "現在のモデルで画像を再生成しますか？",
                en: "Regenerate images for the current model?",
                zh: "要使用当前模型重新生成图片吗？"
            ),
            isPresented: $showRegenerateConfirm
        ) {
            Button(t(ja: "再生成", en: "Regenerate", zh: "重新生成"), role: .destructive) {
                Task { await regenerateImagesForSelectedModel() }
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "現在表示中の投稿画像キャッシュを削除して、選択中モデルで再生成します。",
                    en: "Cached post images will be removed and regenerated with the selected model.",
                    zh: "当前显示的帖子图片缓存将被删除，并使用所选模型重新生成。"
                )
            )
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            timelineBackground
            currentTabContent

            if selectedTab == .timeline {
                floatingNewPostButton
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isChromeHidden)
        .overlay(alignment: .bottom) {
            bottomOverlay
        }
        .sheet(isPresented: $showNewPost) {
            NewPostView(
                posts: $postList.items,
                onSemanticProcessingWillStart: {
                    Task { await suspendImageGenerationForPosting() }
                },
                onSemanticProcessingDidFinish: {
                    Task { await resumeImageGenerationAfterPosting() }
                }
            )
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView { items in
                unreadNotificationCount = items.filter { !$0.isRead }.count
            }
        }
        .sheet(isPresented: $showInstallModels) {
            InstallModelsView(modelManager: modelManager)
        }
        .onAppear {
            let hasSeen = UserDefaults.standard.bool(forKey: "hasSeenInstallPrompt")
            if !modelManager.isModelInstalled && !hasSeen {
                showInstallModels = true
                UserDefaults.standard.set(true, forKey: "hasSeenInstallPrompt")
            }
            Task { await refreshCurrentProfileStats() }
        }
        .onDisappear {
            generationTask?.cancel()
            generationTask = nil
            Task { await generator?.unloadResources() }
        }
    }
}

extension ContentView {

    @ViewBuilder
    private var currentTabContent: some View {
        switch selectedTab {
        case .timeline:
            timelineTab
        case .following:
            followingTab
        case .myPosts:
            myPostsTab
        case .liked:
            likedTab
        }
    }

    private var timelineTab: some View {
        NavigationStack {
            feedBody
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
                .toolbar {
                    profileToolbarButton
                    notificationsToolbarButton
                    timelineLogo
                }
        }
    }

    private var followingTab: some View {
        NavigationStack {
            Group {
                if authManager.isAuthenticated {
                    postsListContent(
                        posts: blockManager.filterBlocked(from: followingPostList.items),
                        isLoading: isLoadingFollowingFeed,
                        emptyText: t(ja: "フォロー中ユーザーの投稿はまだありません", en: "No posts from people you follow yet", zh: "你关注的人还没有帖子"),
                        onRefresh: loadFollowingFeed,
                        onLoadNext: loadNextFollowingPage
                    )
                } else {
                    loginRequiredView(
                        title: t(ja: "フォロー中タイムラインを見るにはログイン", en: "Sign in to see following feed", zh: "登录后查看关注动态"),
                        description: t(ja: "フォローしたユーザーの新着だけを追えます。", en: "See posts only from people you follow.", zh: "只查看你关注用户的帖子。")
                    )
                }
            }
            .navigationTitle(t(ja: "フォロー中", en: "Following", zh: "关注中"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                profileToolbarButton
                notificationsToolbarButton
            }
        }
        .task {
            guard !hasLoadedFollowingFeed else { return }
            await loadFollowingFeed()
        }
    }

    private var myPostsTab: some View {
        NavigationStack {
            Group {
                if authManager.isAuthenticated {
                    postsListContent(
                        posts: blockManager.filterBlocked(from: myPostList.items),
                        isLoading: isLoadingMyPosts,
                        emptyText: t(ja: "自分の投稿はまだありません", en: "No posts yet", zh: "还没有帖子"),
                        onRefresh: loadMyPosts,
                        onLoadNext: loadNextMyPage
                    )
                } else {
                    loginRequiredView(
                        title: t(ja: "投稿履歴を見るにはログイン", en: "Sign in to see your posts", zh: "登录后查看你的帖子"),
                        description: t(ja: "この端末で投稿した履歴や下書きを管理できます。", en: "Manage your post history on this device.", zh: "可以管理你在此设备上的发帖记录和草稿。")
                    )
                }
            }
            .navigationTitle(t(ja: "自分の投稿", en: "My Posts", zh: "我的帖子"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                profileToolbarButton
                notificationsToolbarButton
            }
        }
        .task {
            guard !hasLoadedMyPosts else { return }
            await loadMyPosts()
        }
    }

    private var likedTab: some View {
        NavigationStack {
            Group {
                if authManager.isAuthenticated {
                    postsListContent(
                        posts: blockManager.filterBlocked(from: likedPostList.items),
                        isLoading: isLoadingLikedPosts,
                        emptyText: t(ja: "いいねした投稿はまだありません", en: "No liked posts yet", zh: "还没有点赞的帖子"),
                        onRefresh: loadLikedPosts,
                        onLoadNext: loadNextLikedPage
                    )
                } else {
                    loginRequiredView(
                        title: t(ja: "いいね履歴を見るにはログイン", en: "Sign in to see liked posts", zh: "登录后查看点赞记录"),
                        description: t(ja: "気になった投稿を後から見返せます。", en: "Save and revisit posts you liked.", zh: "保存并重新查看你点赞过的帖子。")
                    )
                }
            }
            .navigationTitle(t(ja: "いいね", en: "Liked", zh: "已点赞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                profileToolbarButton
                notificationsToolbarButton
            }
        }
        .task {
            guard !hasLoadedLikedPosts else { return }
            await loadLikedPosts()
        }
    }

    @MainActor
    func handleAuthenticationChange(isAuthenticated: Bool) async {
        hasLoadedMyPosts = false
        hasLoadedLikedPosts = false
        hasLoadedFollowingFeed = false

        if isAuthenticated {
            await blockManager.refreshFromServerIfPossible()
            await loadFollowingFeed()
            await loadMyPosts()
            await loadLikedPosts()
            await refreshUnreadNotificationsIfNeeded(force: true)
            await refreshCurrentProfileStats()
        } else {
            followingPostList.items = []
            myPostList.items = []
            likedPostList.items = []
            currentFollowingPage = 0
            currentMyPage = 0
            currentLikedPage = 0
            unreadNotificationCount = 0
            currentProfileStats = nil
        }
    }

    func bootSequence() async {
        genLog = t(ja: "準備完了", en: "Ready")

        // ユーザー登録
        let user = userManager.currentUser
        if !user.id.isEmpty {
            await UserService.register(user)
            await blockManager.refreshFromServerIfPossible()
        }

        // モデル未インストールなら即 ready
        guard modelManager.sdInstalled else {
            appBootState = .ready
            await loadInitialPage()
            return
        }

        appBootState = .preparingModel

        // SD 初期化（ここで固まっても OK）
        let sdDir = modelManager.selectedSDModelDirectory

        do {
            let gen = try ImageGenerator(modelsDirectory: sdDir)
            self.generator = gen
            self.isGeneratorReady = true
            self.loadedSDModelID = modelManager.selectedSDModelID
        } catch {
            #if DEBUG
            print("❌ SD init failed:", error)
            #endif
            self.generator = nil
            self.isGeneratorReady = false
            self.loadedSDModelID = nil
        }

        appBootState = .ready
        await loadInitialPage()
        await refreshUnreadNotificationsIfNeeded(force: true)
    }
}

extension ContentView {

    @ViewBuilder
    private var feedBody: some View {
        VStack(spacing: 0) {
            if postList.items.isEmpty && isLoadingFeed {
                ProgressView(t(ja: "フィードを取得中...", en: "Fetching feed..."))
                    .padding(.top, 40)

            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !authManager.isAuthenticated {
                            guestLoginBanner
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                        ForEach(postList.items) { post in
                            PostCardView(
                                post: post,
                                isModelInstalled: modelManager.sdInstalled,
                                onUserBlocked: removeBlockedUserFromLists,
                                onPostReported: removeReportedPostFromLists
                            )
                            .onAppear {
                                if post.id == postList.items.last?.id {
                                    Task { await loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .padding(.bottom, 94)
                }
                .refreshable {
                    await refreshFeed()
                }
                .simultaneousGesture(scrollChromeGesture)
            }
        }
    }
}

extension ContentView {
    private var floatingNewPostButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    if authManager.isAuthenticated {
                        showNewPost = true
                    } else {
                        showLoginSheet = true
                    }
                }) {
                    if authManager.isAuthenticated {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor,
                                            Color.accentColor.opacity(0.78)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 62, height: 62)
                                .shadow(color: Color.accentColor.opacity(0.28), radius: 18, y: 10)

                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                            Text(t(ja: "ログインして投稿", en: "Sign in to post"))
                                .fontWeight(.semibold)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(radius: 3)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, isChromeHidden ? 24 : 74)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            if !isChromeHidden {
                customTabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.18), value: isChromeHidden)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            customTabBarButton(for: .timeline, systemImage: "house", title: t(ja: "ホーム", en: "Home", zh: "首页"))
            customTabBarButton(for: .following, systemImage: "person.2", title: t(ja: "フォロー中", en: "Following", zh: "关注中"))
            customTabBarButton(for: .myPosts, systemImage: "person.text.rectangle", title: t(ja: "投稿", en: "Posts", zh: "帖子"))
            customTabBarButton(for: .liked, systemImage: "heart", title: t(ja: "いいね", en: "Liked", zh: "已点赞"))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.08), radius: 16, y: 8)
    }

    private func customTabBarButton(for tab: HomeTab, systemImage: String, title: String) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
                isChromeHidden = false
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ToolbarContentBuilder
    private var timelineLogo: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private var profileToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showProfileDrawer = true
                }
            } label: {
                if !userManager.currentUser.avatarUrl.isEmpty {
                    CachedAvatarView(urlString: userManager.currentUser.avatarUrl) {
                        profileToolbarFallback
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                } else {
                    profileToolbarFallback
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t(ja: "プロフィールを開く", en: "Open profile"))
        }
    }

    private var profileToolbarFallback: some View {
        Circle()
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            )
    }

    @ToolbarContentBuilder
    private var notificationsToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if authManager.isAuthenticated {
                    showNotifications = true
                } else {
                    showLoginSheet = true
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unreadNotificationCount > 0 ? "bell.fill" : "bell")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(unreadNotificationCount > 0 ? Color.accentColor : Color.primary)
                        .padding(6)
                        .background(
                            unreadNotificationCount > 0
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear,
                            in: Circle()
                        )
                    if unreadNotificationCount > 0 {
                        Text(unreadBadgeText)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, unreadNotificationCount > 9 ? 5 : 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 12, y: -10)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                authManager.isAuthenticated
                ? t(ja: "通知を開く", en: "Open notifications")
                : t(ja: "ログインして通知を見る", en: "Sign in to view notifications")
            )
        }
    }

    private var unreadBadgeText: String {
        unreadNotificationCount > 99 ? "99+" : String(unreadNotificationCount)
    }

    private var profileDrawerOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(showProfileDrawer ? 0.4 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(showProfileDrawer)
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showProfileDrawer = false
                    }
                }

            NavigationStack {
                profileDrawerMenu
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.82, 340))
            .frame(maxHeight: .infinity)
            .background(drawerBackgroundColor)
            .offset(x: drawerOffsetX)
            // Keep the drawer's close swipe without stealing vertical drags from
            // nested ScrollViews such as the AI Models screen.
            .simultaneousGesture(profileDrawerSwipeGesture)
            .shadow(color: Color.black.opacity(showProfileDrawer ? 0.18 : 0), radius: 18, x: 8, y: 0)
        }
        .allowsHitTesting(showProfileDrawer)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.88), value: showProfileDrawer)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.92), value: profileDrawerDragTranslation)
    }

    private var profileDrawerMenu: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                profileDrawerHeader

                profileDrawerPrimarySection
                    .padding(.top, 24)

                Divider()
                    .overlay(Color(.separator))
                    .padding(.vertical, 24)

                profileDrawerSecondarySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(drawerBackgroundColor.ignoresSafeArea())
        .tint(drawerPrimaryTextColor)
    }

    private var profileDrawerHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Group {
                    if !userManager.currentUser.avatarUrl.isEmpty {
                        CachedAvatarView(urlString: userManager.currentUser.avatarUrl) {
                            Circle().fill(drawerSecondaryFillColor)
                        }
                    } else {
                        Circle()
                            .fill(drawerSecondaryFillColor)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(drawerPrimaryTextColor.opacity(0.8))
                            )
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showProfileDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(drawerPrimaryTextColor)
                        .frame(width: 36, height: 36)
                        .background(drawerSecondaryFillColor, in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(userManager.currentUser.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(drawerPrimaryTextColor)
                    .lineLimit(2)

                if !userManager.currentUser.id.isEmpty {
                    Text("@\(userManager.currentUser.id)")
                        .font(.subheadline)
                        .foregroundColor(drawerSecondaryTextColor)
                        .textSelection(.enabled)
                }

                if let email = userManager.currentUser.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(drawerTertiaryTextColor)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 24) {
                profileStatText(
                    value: currentProfileStats?.followingCount ?? 0,
                    label: t(ja: "フォロー中", en: "Following", zh: "关注中")
                )
                profileStatText(
                    value: currentProfileStats?.followerCount ?? 0,
                    label: t(ja: "フォロワー", en: "Followers", zh: "粉丝")
                )
            }
            .padding(.top, 4)
        }
    }

    private var profileDrawerPrimarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileDrawerLink(
                title: t(ja: "プロフィール", en: "Profile", zh: "个人资料"),
                systemImage: "person"
            ) {
                UserProfileView(showsCloseButton: false, showAppSettings: false)
            }

            profileDrawerLink(
                title: t(ja: "AIモデル", en: "AI Models", zh: "AI 模型"),
                systemImage: "cpu"
            ) {
                ModelManagementView()
            }

            profileDrawerLink(
                title: t(ja: "ブロック管理", en: "Blocked Users", zh: "屏蔽管理"),
                systemImage: "person.2.slash"
            ) {
                BlockedUsersView()
            }
        }
    }

    private var profileDrawerSecondarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileDrawerLink(
                title: t(ja: "設定とプライバシー", en: "Settings and Privacy", zh: "设置与隐私"),
                systemImage: "gearshape"
            ) {
                SettingsView()
            }

            if authManager.isAuthenticated {
                Button {
                    Task { await authManager.logout() }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showProfileDrawer = false
                    }
                } label: {
                    profileDrawerRow(
                        title: t(ja: "ログアウト", en: "Log Out", zh: "退出登录"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDestructive: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showLoginSheet = true
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showProfileDrawer = false
                    }
                } label: {
                    profileDrawerRow(
                        title: t(ja: "メールでログイン", en: "Sign in with Email", zh: "使用邮箱登录"),
                        systemImage: "envelope"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func profileDrawerLink<Destination: View>(
        title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            profileDrawerRow(title: title, systemImage: systemImage)
        }
        .simultaneousGesture(TapGesture().onEnded {
            profileDrawerDragTranslation = 0
        })
    }

    private func profileDrawerRow(title: String, systemImage: String, isDestructive: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .medium))
                .frame(width: 28)
                .foregroundColor(isDestructive ? .red.opacity(0.9) : drawerPrimaryTextColor.opacity(0.95))

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isDestructive ? .red.opacity(0.9) : drawerPrimaryTextColor)

            Spacer()
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func profileStatText(value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
                .foregroundColor(drawerPrimaryTextColor)
            Text(label)
                .font(.subheadline)
                .foregroundColor(drawerSecondaryTextColor)
        }
    }

    private var drawerBackgroundColor: Color {
        Color(.systemBackground)
    }

    private var drawerPrimaryTextColor: Color {
        Color.primary
    }

    private var drawerSecondaryTextColor: Color {
        Color.secondary
    }

    private var drawerTertiaryTextColor: Color {
        Color.secondary.opacity(0.82)
    }

    private var drawerSecondaryFillColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08)
    }

    private var drawerWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.82, 340)
    }

    private var drawerOffsetX: CGFloat {
        if showProfileDrawer {
            return min(profileDrawerDragTranslation, 0)
        }
        return -drawerWidth
    }

    private var profileDrawerEdgeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                guard !showProfileDrawer else { return }
                guard value.startLocation.x <= 28 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width > 0 {
                    profileDrawerDragTranslation = max(value.translation.width - drawerWidth, -drawerWidth)
                }
            }
            .onEnded { value in
                defer { profileDrawerDragTranslation = 0 }
                guard value.startLocation.x <= 28 else { return }
                guard value.translation.width > 70 else { return }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                    showProfileDrawer = true
                }
            }
    }

    private var profileDrawerSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                guard showProfileDrawer else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    profileDrawerDragTranslation = value.translation.width
                }
            }
            .onEnded { value in
                defer { profileDrawerDragTranslation = 0 }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical else { return }

                if showProfileDrawer {
                    guard horizontal < -70 else { return }
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                        showProfileDrawer = false
                    }
                    return
                }

                guard value.startLocation.x <= 28, horizontal > 70 else { return }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                    showProfileDrawer = true
                }
            }
    }

    private var guestLoginBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t(ja: "ゲスト閲覧中", en: "Browsing as Guest"))
                .font(.subheadline.weight(.bold))
            Text(
                t(
                    ja: "投稿・いいね・ブロックはログイン後に利用できます。",
                    en: "Posting, likes, and block controls are available after sign-in.",
                    zh: "发帖、点赞和屏蔽功能需登录后使用。"
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Button {
                showLoginSheet = true
            } label: {
                Text(t(ja: "メールでログイン", en: "Sign in with Email", zh: "使用邮箱登录"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        )
    }

    private var scrollChromeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !showProfileDrawer else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                if value.translation.height < -14, !isChromeHidden {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isChromeHidden = true
                    }
                } else if value.translation.height > 14, isChromeHidden {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isChromeHidden = false
                    }
                }
            }
    }

    @MainActor
    private func refreshCurrentProfileStats() async {
        guard authManager.isAuthenticated else {
            currentProfileStats = nil
            return
        }
        let userId = userManager.currentUser.id
        guard !userId.isEmpty else {
            currentProfileStats = nil
            return
        }

        do {
            currentProfileStats = try await FollowService.fetchPublicProfile(userId: userId)
        } catch {
            if currentProfileStats == nil {
                currentProfileStats = PublicUserProfile(
                    id: userId,
                    displayName: userManager.currentUser.displayName,
                    avatarUrl: userManager.currentUser.avatarUrl,
                    bio: userManager.currentUser.bio,
                    followerCount: 0,
                    followingCount: 0,
                    postCount: 0,
                    isFollowing: false
                )
            }
        }
    }

    @ViewBuilder
    private func postsListContent(
        posts: [Post],
        isLoading: Bool,
        emptyText: String,
        onRefresh: @escaping () async -> Void,
        onLoadNext: @escaping () async -> Void
    ) -> some View {
        if posts.isEmpty && isLoading {
            ProgressView(t(ja: "読み込み中...", en: "Loading..."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if posts.isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(posts) { post in
                        PostCardView(
                            post: post,
                            isModelInstalled: modelManager.sdInstalled,
                            onUserBlocked: removeBlockedUserFromLists,
                            onPostReported: removeReportedPostFromLists
                        )
                            .onAppear {
                                if post.id == posts.last?.id {
                                    Task { await onLoadNext() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 88)
            }
            .refreshable {
                await onRefresh()
            }
            .simultaneousGesture(scrollChromeGesture)
        }
    }

    @ViewBuilder
    private func loginRequiredView(title: String, description: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                showLoginSheet = true
            } label: {
                Text(t(ja: "ログインする", en: "Sign In"))
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var timelineBackground: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }

    private func removeBlockedUserFromLists(_ blockedUserId: String) {
        postList.items.removeAll { $0.userId == blockedUserId }
        followingPostList.items.removeAll { $0.userId == blockedUserId }
        myPostList.items.removeAll { $0.userId == blockedUserId }
        likedPostList.items.removeAll { $0.userId == blockedUserId }
        showBlockToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            showBlockToast = false
        }
    }

    private func removeReportedPostFromLists(_ postId: String) {
        postList.items.removeAll { $0.id == postId }
        followingPostList.items.removeAll { $0.id == postId }
        myPostList.items.removeAll { $0.id == postId }
        likedPostList.items.removeAll { $0.id == postId }
        showReportToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            showReportToast = false
        }
    }

    @MainActor
    private func refreshUnreadNotificationsIfNeeded(force: Bool = false) async {
        guard authManager.isAuthenticated else {
            unreadNotificationCount = 0
            PushNotificationManager.shared.clearBadges()
            return
        }

        if showNotifications && !force {
            unreadNotificationCount = 0
            PushNotificationManager.shared.clearBadges()
            return
        }

        do {
            let notifications = try await NotificationService.fetchNotifications(limit: 30)
            unreadNotificationCount = notifications.filter { !$0.isRead }.count
            PushNotificationManager.shared.setBadgeCount(unreadNotificationCount)
        } catch {
            if force {
                unreadNotificationCount = 0
                PushNotificationManager.shared.clearBadges()
            }
        }
    }
}

extension ContentView {

    func loadInitialPage() async {
        isLoadingFeed = true
        do {
            let firstPage = try await FeedLoader.fetchPage(page: 0, pageSize: pageSize)
            let filtered = blockManager.filterBlocked(from: firstPage)
            postList.items = filtered
            currentPage = 0
            isLoadingFeed = false

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "❌ フィードの読み込みに失敗", en: "❌ Failed to load feed")
            isLoadingFeed = false
        }
    }

    func loadFollowingFeed() async {
        guard authManager.isAuthenticated else {
            followingPostList.items = []
            hasLoadedFollowingFeed = true
            return
        }
        guard !isLoadingFollowingFeed else { return }
        isLoadingFollowingFeed = true
        defer { isLoadingFollowingFeed = false }
        hasLoadedFollowingFeed = true

        do {
            let firstPage = try await FeedLoader.fetchFollowingFeed(page: 0, pageSize: pageSize)
            let filtered = blockManager.filterBlocked(from: firstPage)
            followingPostList.items = filtered
            currentFollowingPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ フォロー中タイムラインの読み込みに失敗", en: "⚠️ Failed to load following feed")
        }
    }

    func loadNextFollowingPage() async {
        guard authManager.isAuthenticated else { return }
        guard !isLoadingFollowingFeed else { return }
        isLoadingFollowingFeed = true
        defer { isLoadingFollowingFeed = false }

        do {
            let next = try await FeedLoader.fetchFollowingFeed(
                page: currentFollowingPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else { return }

            let filtered = blockManager.filterBlocked(from: next)
            followingPostList.items.append(contentsOf: filtered)
            currentFollowingPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ フォロー中タイムラインの続き取得に失敗", en: "⚠️ Failed to load more following posts")
        }
    }

    func loadNextPage() async {
        guard !isLoadingFeed else { return }
        isLoadingFeed = true

        do {
            let next = try await FeedLoader.fetchPage(
                page: currentPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else {
                isLoadingFeed = false
                return
            }

            let filtered = blockManager.filterBlocked(from: next)
            postList.items.append(contentsOf: filtered)
            currentPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ ページ読み込みに失敗", en: "⚠️ Page load failed")
        }

        isLoadingFeed = false
    }

    func refreshFeed() async {
        do {
            let latest = try await FeedLoader.fetchPage(page: 0, pageSize: pageSize)
            let existing = Set(postList.items.map { $0.id })
            let newPosts = blockManager.filterBlocked(from: latest)
                .filter { !existing.contains($0.id) }

            guard !newPosts.isEmpty else { return }
            postList.items.insert(contentsOf: newPosts, at: 0)

            enqueueImages(for: newPosts)
        } catch {
            genLog = t(ja: "⚠️ 更新に失敗", en: "⚠️ Refresh failed")
        }
    }

    func loadMyPosts() async {
        guard !isLoadingMyPosts else { return }
        let userId = userManager.currentUser.id
        guard !userId.isEmpty else {
            myPostList.items = []
            hasLoadedMyPosts = true
            return
        }
        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }
        hasLoadedMyPosts = true

        do {
            let first = try await FeedLoader.fetchMyPosts(
                userId: userId,
                page: 0,
                pageSize: pageSize
            )
            let filtered = filterMyPosts(blockManager.filterBlocked(from: first))
            myPostList.items = filtered
            currentMyPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ 自分の投稿の読み込みに失敗", en: "⚠️ Failed to load my posts")
            let userId = userManager.currentUser.id
            myPostList.items = blockManager.filterBlocked(from: postList.items.filter { $0.userId == userId })
        }
    }

    func loadNextMyPage() async {
        guard !isLoadingMyPosts else { return }
        let userId = userManager.currentUser.id
        guard !userId.isEmpty else { return }
        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }

        do {
            let next = try await FeedLoader.fetchMyPosts(
                userId: userId,
                page: currentMyPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else { return }
            let filtered = filterMyPosts(blockManager.filterBlocked(from: next))
            myPostList.items.append(contentsOf: filtered)
            currentMyPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ 自分の投稿ページ読み込みに失敗", en: "⚠️ Failed to load my posts page")
        }
    }

    func loadLikedPosts() async {
        guard !isLoadingLikedPosts else { return }
        let userId = userManager.currentUser.id
        guard !userId.isEmpty else {
            likedPostList.items = []
            hasLoadedLikedPosts = true
            return
        }
        isLoadingLikedPosts = true
        defer { isLoadingLikedPosts = false }
        hasLoadedLikedPosts = true

        do {
            let first = try await FeedLoader.fetchLikedPosts(
                userId: userId,
                page: 0,
                pageSize: pageSize
            )
            let filtered = blockManager.filterBlocked(from: first)
            likedPostList.items = filtered
            currentLikedPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ いいね投稿の読み込みに失敗", en: "⚠️ Failed to load liked posts")
            likedPostList.items = blockManager.filterBlocked(from: postList.items.filter { $0.isLikedByCurrentUser == true })
        }
    }

    func loadNextLikedPage() async {
        guard !isLoadingLikedPosts else { return }
        let userId = userManager.currentUser.id
        guard !userId.isEmpty else { return }
        isLoadingLikedPosts = true
        defer { isLoadingLikedPosts = false }

        do {
            let next = try await FeedLoader.fetchLikedPosts(
                userId: userId,
                page: currentLikedPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else { return }
            let filtered = blockManager.filterBlocked(from: next)
            likedPostList.items.append(contentsOf: filtered)
            currentLikedPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLog = t(ja: "⚠️ いいね投稿ページ読み込みに失敗", en: "⚠️ Failed to load liked posts page")
        }
    }

    @MainActor
    func enqueueImages(for posts: [Post]) {
        guard !isGenerationSuspendedForPosting else { return }
        let canGenerate = modelManager.sdInstalled
        let modelID = modelManager.selectedSDModelID
        for post in posts {
            guard post.hasImage else {
                post.previewImage = nil
                post.clearRegenerationEvaluation()
                continue
            }
            let evaluationKey = regenerationEvaluationCacheKey(postID: post.id, modelID: modelID)
            if let savedEvaluation = ImageCacheManager.shared.loadRegenerationEvaluation(for: evaluationKey) {
                post.regenerationEvaluation = savedEvaluation
            }
            let cacheKey = post.effectivePrompt.map { generatedCacheKey(for: post, modelID: modelID, prompt: $0) }
            if let cacheKey,
               let cached = ImageCacheManager.shared.load(for: cacheKey) {
                post.localImage = cached
                scheduleSemanticFidelityUpdateIfNeeded(for: post, generatedImage: cached, modelID: modelID)
            } else {
                post.semanticFidelityScore = nil
                if post.previewImage == nil {
                    post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
                }
                if canGenerate, !generationQueue.contains(where: { $0.id == post.id }) {
                    generationQueue.append(post)
                }
            }
        }

        prioritizeGenerationForCurrentContext()

        guard canGenerate else { return }
        guard !isGenerating else { return }
        isGenerating = true
        generationTask = Task { await processQueue() }
    }

    @MainActor
    func processQueue() async {
        defer {
            isGenerating = false
            generationTask = nil
        }

        guard let generator else {
            return
        }

        while !generationQueue.isEmpty {
            if isGenerationSuspendedForPosting { return }
            if Task.isCancelled { return }
            let post = generationQueue.removeFirst()
            guard let prompt = post.effectivePrompt else { continue }
            let modelID = modelManager.selectedSDModelID
            let rawInitImage = post.makeInitImage()
            let initImage: UIImage? = (modelID == ModelManager.sd15LCMModelID) ? nil : rawInitImage
            let hasInit = (initImage != nil)
            let enhancedPrompt = hasInit
                ? "\(prompt), sharp focus, fine detail, highly detailed, crisp texture, high clarity"
                : prompt
            let negativePrompt = hasInit
                ? "blurry, soft focus, low detail, lowres, out of focus"
                : ""
            let profile = SDModeProfile.forMode(post.privacyMode, modelID: modelID)
            let cacheKey = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
            let generationStart = Date()

            do {
                let img = try await generator.generateImage(
                    from: enhancedPrompt,
                    negativePrompt: negativePrompt,
                    initImage: initImage,
                    strength: profile.denoiseStrength,
                    steps: profile.stepCount,
                    guidance: profile.guidanceScale
                )
                post.localImage = img
                post.previewImage = nil
                ImageCacheManager.shared.save(img, for: cacheKey)
                ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
                scheduleSemanticFidelityUpdateIfNeeded(for: post, generatedImage: img, modelID: modelID)
                updateImageGenerationDiagnosticsIfNeeded(for: post, generationStart: generationStart, modelID: modelID)
            } catch {
                #if DEBUG
                print("⚠️ Image generation failed:", error)
                #endif
                do {
                    let fallback = try await generator.generateImage(
                        from: enhancedPrompt,
                        negativePrompt: negativePrompt,
                        initImage: nil,
                        steps: profile.stepCount,
                        guidance: profile.guidanceScale
                    )
                    post.localImage = fallback
                    post.previewImage = nil
                    ImageCacheManager.shared.save(fallback, for: cacheKey)
                    ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
                    scheduleSemanticFidelityUpdateIfNeeded(for: post, generatedImage: fallback, modelID: modelID)
                    updateImageGenerationDiagnosticsIfNeeded(for: post, generationStart: generationStart, modelID: modelID)
                } catch {
                    #if DEBUG
                    print("⚠️ Fallback generation failed:", error)
                    #endif
                    updateImageGenerationDiagnosticsIfNeeded(for: post, generationStart: generationStart, modelID: modelID)
                    post.previewImage = nil
                }
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }

    private func localizeGenLogIfNeeded() {
        let map: [(ja: String, en: String)] = [
            ("準備完了", "Ready"),
            ("❌ フィードの読み込みに失敗", "❌ Failed to load feed"),
            ("⚠️ ページ読み込みに失敗", "⚠️ Page load failed"),
            ("⚠️ 更新に失敗", "⚠️ Refresh failed"),
            ("⚠️ 自分の投稿の読み込みに失敗", "⚠️ Failed to load my posts"),
            ("⚠️ 自分の投稿ページ読み込みに失敗", "⚠️ Failed to load my posts page"),
            ("⚠️ いいね投稿の読み込みに失敗", "⚠️ Failed to load liked posts"),
            ("⚠️ いいね投稿ページ読み込みに失敗", "⚠️ Failed to load liked posts page"),
        ]

        for pair in map {
            if genLog == pair.ja || genLog == pair.en {
                genLog = t(ja: pair.ja, en: pair.en)
                break
            }
        }
    }

    private func filterMyPosts(_ posts: [Post]) -> [Post] {
        posts.filter { post in
            if post.hasImage {
                let promptEmpty = (post.effectivePrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if post.status != .completed && promptEmpty {
                    return false
                }
            }
            return true
        }
    }

    @MainActor
    private func regenerateImagesForSelectedModel() async {
        let modelID = modelManager.selectedSDModelID
        let allPosts = allKnownPosts

        for post in allPosts {
            guard let prompt = post.effectivePrompt else { continue }
            let key = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
            ImageCacheManager.shared.remove(for: key)
            ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
            post.localImage = nil
            post.clearRegenerationEvaluation()
            if post.hasImage {
                post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
            } else {
                post.previewImage = nil
            }
        }

        generationQueue.removeAll()
        enqueueImages(for: allPosts)
    }
}

extension ContentView {
    private var allKnownPosts: [Post] {
        var seen: Set<String> = []
        var result: [Post] = []
        for post in postList.items + followingPostList.items + myPostList.items + likedPostList.items {
            if seen.insert(post.id).inserted {
                result.append(post)
            }
        }
        return result
    }

    private var postsForSelectedTab: [Post] {
        switch selectedTab {
        case .timeline:
            return postList.items
        case .following:
            return followingPostList.items
        case .myPosts:
            return myPostList.items
        case .liked:
            return likedPostList.items
        }
    }

    private func isCurrentUsersPost(_ post: Post) -> Bool {
        guard let userID = post.userId, !userID.isEmpty else { return false }
        return userID == userManager.currentUser.id
    }

    @MainActor
    private func prioritizeGenerationForCurrentContext(using supplementalPosts: [Post] = []) {
        let ids = externallyPrioritizedPostIDs.isEmpty
            ? postsForSelectedTab.map(\.id)
            : externallyPrioritizedPostIDs
        let prioritizedIDs = Set(ids)
        guard !prioritizedIDs.isEmpty else { return }

        let supplementalByID = Dictionary(uniqueKeysWithValues: supplementalPosts.map { ($0.id, $0) })
        for id in ids.reversed() {
            guard let post = supplementalByID[id] else { continue }
            guard post.hasImage, post.effectivePrompt != nil else { continue }
            guard post.localImage == nil else { continue }
            if !generationQueue.contains(where: { $0.id == id }) {
                generationQueue.insert(post, at: 0)
            }
        }

        let prioritized = generationQueue.filter { prioritizedIDs.contains($0.id) }
        let remaining = generationQueue.filter { !prioritizedIDs.contains($0.id) }
        generationQueue = prioritized + remaining

        if !generationQueue.isEmpty, !isGenerating, generator != nil {
            isGenerating = true
            generationTask = Task { await processQueue() }
        }
    }

    @MainActor
    private func regenerateImage(for postID: String, post explicitPost: Post? = nil) async {
        let post = explicitPost ?? allKnownPosts.first(where: { $0.id == postID })
        guard let post else { return }
        guard let prompt = post.effectivePrompt else { return }

        let modelID = modelManager.selectedSDModelID
        let key = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
        ImageCacheManager.shared.remove(for: key)
        ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
        post.localImage = nil
        post.clearRegenerationEvaluation()
        post.previewImage = post.hasImage
            ? post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
            : nil

        generationQueue.removeAll { $0.id == postID }
        generationQueue.insert(post, at: 0)

        if !isGenerating, modelManager.sdInstalled {
            isGenerating = true
            generationTask = Task { await processQueue() }
        }
    }

    private func semanticScoreKey(for post: Post, modelID: String) -> String {
        regenerationEvaluationCacheKey(postID: post.id, modelID: modelID)
    }

    private func generatedCacheKey(for post: Post, modelID: String, prompt: String) -> String {
        "\(modelID)::\(post.mode)::\(post.id)::\(prompt)"
    }

    @MainActor
    private func scheduleSemanticFidelityUpdateIfNeeded(for post: Post, generatedImage: UIImage, modelID: String) {
        guard post.hasImage, isCurrentUsersPost(post) else {
            post.semanticFidelityScore = nil
            return
        }

        guard let originalImage = ImageCacheManager.shared.load(for: post.id, namespace: .originalImages) else {
            post.semanticFidelityScore = nil
            return
        }

        let scoreKey = semanticScoreKey(for: post, modelID: modelID)
        if let cachedScore = ImageCacheManager.shared.loadSemanticScore(for: scoreKey) {
            post.semanticFidelityScore = cachedScore
            return
        }

        guard !semanticScoreTasks.contains(scoreKey) else { return }
        semanticScoreTasks.insert(scoreKey)

        Task {
            let score = await computeSemanticFidelityScore(original: originalImage, regenerated: generatedImage)
            await MainActor.run {
                semanticScoreTasks.remove(scoreKey)
                guard let score else {
                    post.semanticFidelityScore = nil
                    persistRegenerationEvaluationIfAvailable(for: post, modelID: modelID)
                    return
                }
                post.semanticFidelityScore = score
                persistRegenerationEvaluationIfAvailable(for: post, modelID: modelID)
            }
        }
    }

    @MainActor
    private func persistRegenerationEvaluationIfAvailable(for post: Post, modelID: String) {
        let key = regenerationEvaluationCacheKey(postID: post.id, modelID: modelID)
        if let evaluation = post.regenerationEvaluation {
            ImageCacheManager.shared.saveRegenerationEvaluation(evaluation, for: key)
        } else {
            ImageCacheManager.shared.removeSemanticScore(for: key)
        }
    }

    private func computeSemanticFidelityScore(original: UIImage, regenerated: UIImage) async -> Double? {
        do {
            let originalEmbedding = try await SigLIP2Service.shared.embed(image: original)
            let regeneratedEmbedding = try await SigLIP2Service.shared.embed(image: regenerated)
            return cosineSimilarity(originalEmbedding, regeneratedEmbedding)
        } catch {
            #if DEBUG
            print("⚠️ Semantic fidelity scoring failed:", error)
            #endif
            return nil
        }
    }

    private var isProModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferences.proModeEnabledKey)
    }

    @MainActor
    private func updateImageGenerationDiagnosticsIfNeeded(
        for post: Post,
        generationStart: Date,
        modelID: String
    ) {
        guard isProModeEnabled else { return }
        post.updateImageGenerationDiagnostics(
            duration: Date().timeIntervalSince(generationStart),
            memoryMB: currentMemoryFootprintMB()
        )
        persistRegenerationEvaluationIfAvailable(for: post, modelID: modelID)
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }

        var dot: Double = 0
        var lhsNorm: Double = 0
        var rhsNorm: Double = 0

        for index in lhs.indices {
            let a = Double(lhs[index])
            let b = Double(rhs[index])
            dot += a * b
            lhsNorm += a * a
            rhsNorm += b * b
        }

        let denom = lhsNorm.squareRoot() * rhsNorm.squareRoot()
        guard denom > 0 else { return nil }
        return max(0, min(dot / denom, 1))
    }

    @MainActor
    private func clearAllImageCachesAndRegenerate() async {
        ImageCacheManager.shared.clearAllCaches()

        for post in allKnownPosts {
            post.localImage = nil
            post.clearRegenerationEvaluation()
            if post.hasImage {
                post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
            } else {
                post.previewImage = nil
            }
        }

        generationQueue.removeAll()
        semanticScoreTasks.removeAll()
        enqueueImages(for: allKnownPosts)
    }

    @MainActor
    private func maybeReloadGeneratorForSelectedModel() async {
        guard !isGenerationSuspendedForPosting else { return }
        guard modelManager.sdInstalled else { return }
        guard loadedSDModelID != modelManager.selectedSDModelID || generator == nil else { return }
        await reloadGeneratorForSelectedModel()
    }

    @MainActor
    private func reloadGeneratorForSelectedModel() async {
        guard !isGenerationSuspendedForPosting else { return }
        let previousModelID = loadedSDModelID

        generationTask?.cancel()
        generationTask = nil
        generationQueue.removeAll()
        isGenerating = false

        if let current = generator {
            await current.unloadResources()
            generator = nil
            isGeneratorReady = false
        }

        guard modelManager.sdInstalled else { return }

        do {
            let gen = try ImageGenerator(modelsDirectory: modelManager.selectedSDModelDirectory)
            generator = gen
            isGeneratorReady = true
            loadedSDModelID = modelManager.selectedSDModelID
            genLog = t(ja: "準備完了", en: "Ready")

            if previousModelID != nil && previousModelID != loadedSDModelID {
                clearDisplayedImagesForModelSwitch()
            }
            enqueueImages(for: allKnownPosts)
        } catch {
            #if DEBUG
            print("❌ SD re-init failed:", error)
            #endif
            generator = nil
            isGeneratorReady = false
            loadedSDModelID = nil
            genLog = t(
                ja: "⚠️ モデル切替の反映に失敗。再起動すると改善する場合があります",
                en: "⚠️ Failed to apply model switch. Restarting the app may help."
            )
        }
    }

    @MainActor
    private func clearDisplayedImagesForModelSwitch() {
        let allPosts = allKnownPosts
        for post in allPosts {
            guard post.hasImage else {
                post.localImage = nil
                post.previewImage = nil
                post.clearRegenerationEvaluation()
                continue
            }
            post.localImage = nil
            post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
            post.clearRegenerationEvaluation()
        }
    }

    @MainActor
    private func suspendImageGenerationForPosting() async {
        guard !isGenerationSuspendedForPosting else { return }
        isGenerationSuspendedForPosting = true

        generationTask?.cancel()
        generationTask = nil
        generationQueue.removeAll()
        semanticScoreTasks.removeAll()
        isGenerating = false

        if let current = generator {
            await current.unloadResources()
            generator = nil
            isGeneratorReady = false
        }

        genLog = t(ja: "投稿処理中のため再生成を一時停止", en: "Image generation paused during posting")
    }

    @MainActor
    private func resumeImageGenerationAfterPosting() async {
        guard isGenerationSuspendedForPosting else { return }
        isGenerationSuspendedForPosting = false

        await maybeReloadGeneratorForSelectedModel()
        enqueueImages(for: allKnownPosts)
        if modelManager.sdInstalled {
            genLog = t(ja: "準備完了", en: "Ready")
        }
    }
}

private extension View {
    func toastStyle() -> some View {
        self.font(.footnote)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.78))
            .clipShape(Capsule())
    }
}
