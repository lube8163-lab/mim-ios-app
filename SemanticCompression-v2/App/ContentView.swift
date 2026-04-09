import SwiftUI
import Combine
import CoreML
import CryptoKit

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
    @AppStorage(AppPreferences.forceSDTextToImageKey)
    private var forceSDTextToImage = false

    @State private var showNewPost = false
    @State private var showInstallModels = false
    @State private var selectedTab: HomeTab = .timeline

    @State private var genLogKey = "content.genlog.ready"
    @State private var isLoadingFeed = false
    @State private var isLoadingFollowingFeed = false
    @State private var isLoadingMyPosts = false
    @State private var isLoadingLikedPosts = false

    @State private var generator: ImageGenerator?
    @State private var isGeneratorReady = false
    @State private var loadedGenerationCacheKey: String?

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
    @State private var showLogoutConfirm = false
    @State private var deferStableDiffusionReloadUntilRestart = false

    // MARK: - Body

    var body: some View {
        decoratedContent
    }

    private var rootContent: some View {
        ZStack {
            switch appBootState {
            case .launching, .preparingModel:
                AppLaunchView()

            case .ready:
                mainContent
            }
        }
    }

    private var lifecycleContent: some View {
        rootContent
        .task {
            await bootSequence()
        }
        .onChange(of: modelManager.selectedSDModelID) { _ in
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
        .onChange(of: modelManager.selectedImageGenerationBackendID) { _ in
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
        .onChange(of: modelManager.sdInstalled) { _ in
            Task { await maybeReloadGeneratorForSelectedModel() }
        }
    }

    private var eventContent: some View {
        lifecycleContent
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
        .onReceive(NotificationCenter.default.publisher(for: .deferStableDiffusionReloadUntilRestart)) { _ in
            deferStableDiffusionReloadUntilRestart = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationDidChange)) { _ in
            Task { await refreshUnreadNotificationsIfNeeded(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { notification in
            guard let postId = notification.userInfo?["postId"] as? String else { return }
            removeDeletedPostFromLists(postId)
        }
    }

    private var decoratedContent: some View {
        eventContent
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
                    Text(l("content.toast.report_hidden"))
                        .toastStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showBlockToast {
                    Text(l("content.toast.block_hidden"))
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
        .alert(l("content.alert.regenerate.title"), isPresented: $showRegenerateConfirm) {
            Button(l("content.alert.regenerate.confirm"), role: .destructive) {
                Task { await regenerateImagesForSelectedModel() }
            }
            Button(l("common.cancel"), role: .cancel) {}
        } message: {
            Text(l("content.alert.regenerate.message"))
        }
        .alert(l("content.alert.logout.title"), isPresented: $showLogoutConfirm) {
            Button(l("content.alert.logout.confirm"), role: .destructive) {
                Task { await authManager.logout() }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showProfileDrawer = false
                }
            }
            Button(l("common.cancel"), role: .cancel) {}
        } message: {
            Text(l("content.alert.logout.message"))
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
            if !modelManager.hasAnyDownloadedModel && !hasSeen {
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
                        emptyText: l("content.following.empty"),
                        onRefresh: loadFollowingFeed,
                        onLoadNext: loadNextFollowingPage
                    )
                } else {
                    loginRequiredView(
                        title: l("content.following.login_title"),
                        description: l("content.following.login_description")
                    )
                }
            }
            .navigationTitle(l("content.tab.following"))
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
                        emptyText: l("content.my_posts.empty"),
                        onRefresh: loadMyPosts,
                        onLoadNext: loadNextMyPage
                    )
                } else {
                    loginRequiredView(
                        title: l("content.my_posts.login_title"),
                        description: l("content.my_posts.login_description")
                    )
                }
            }
            .navigationTitle(l("content.tab.my_posts"))
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
                        emptyText: l("content.liked.empty"),
                        onRefresh: loadLikedPosts,
                        onLoadNext: loadNextLikedPage
                    )
                } else {
                    loginRequiredView(
                        title: l("content.liked.login_title"),
                        description: l("content.liked.login_description")
                    )
                }
            }
            .navigationTitle(l("content.tab.liked"))
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
        genLogKey = "content.genlog.ready"

        // ユーザー登録
        let user = userManager.currentUser
        if !user.id.isEmpty {
            await UserService.register(user)
            await blockManager.refreshFromServerIfPossible()
        }

        guard modelManager.resolvedImageGenerationBackend == .stableDiffusion else {
            appBootState = .ready
            loadedGenerationCacheKey = modelManager.activeImageGenerationCacheKey
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
            self.loadedGenerationCacheKey = modelManager.activeImageGenerationCacheKey
        } catch {
            #if DEBUG
            print("❌ SD init failed:", error)
            #endif
            self.generator = nil
            self.isGeneratorReady = false
            self.loadedGenerationCacheKey = nil
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
                ProgressView(l("content.feed.fetching"))
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
                                isModelInstalled: modelManager.canGenerateImages,
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
                            Text(l("content.sign_in_to_post"))
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
            customTabBarButton(for: .timeline, systemImage: "house", title: l("content.tab.home"))
            customTabBarButton(for: .following, systemImage: "person.2", title: l("content.tab.following"))
            customTabBarButton(for: .myPosts, systemImage: "person.text.rectangle", title: l("content.tab.posts"))
            customTabBarButton(for: .liked, systemImage: "heart", title: l("content.tab.liked"))
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
            .accessibilityLabel(l("content.accessibility.open_profile"))
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
                ? l("content.accessibility.open_notifications")
                : l("content.accessibility.sign_in_notifications")
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
                    label: l("content.drawer.following")
                )
                profileStatText(
                    value: currentProfileStats?.followerCount ?? 0,
                    label: l("content.drawer.followers")
                )
            }
            .padding(.top, 4)
        }
    }

    private var profileDrawerPrimarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileDrawerLink(
                title: l("content.drawer.profile"),
                systemImage: "person"
            ) {
                UserProfileView(showsCloseButton: false, showAppSettings: false)
            }

            profileDrawerLink(
                title: l("content.drawer.ai_models"),
                systemImage: "cpu"
            ) {
                ModelManagementView()
            }

            profileDrawerLink(
                title: l("content.drawer.blocked_users"),
                systemImage: "person.2.slash"
            ) {
                BlockedUsersView()
            }
        }
    }

    private var profileDrawerSecondarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            profileDrawerLink(
                title: l("content.drawer.settings"),
                systemImage: "gearshape"
            ) {
                SettingsView()
            }

            if authManager.isAuthenticated {
                Button {
                    showLogoutConfirm = true
                } label: {
                    profileDrawerRow(
                        title: l("content.drawer.log_out"),
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
                        title: l("content.drawer.sign_in_email"),
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
            Text(l("content.guest.title"))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(
                l("content.guest.description")
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Button {
                showLoginSheet = true
            } label: {
                Text(l("content.drawer.sign_in_email"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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
            ProgressView(l("content.loading"))
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
                            isModelInstalled: modelManager.canGenerateImages,
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
                Text(l("content.sign_in"))
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

    private func removeDeletedPostFromLists(_ postId: String) {
        postList.items.removeAll { $0.id == postId }
        followingPostList.items.removeAll { $0.id == postId }
        myPostList.items.removeAll { $0.id == postId }
        likedPostList.items.removeAll { $0.id == postId }
        generationQueue.removeAll { $0.id == postId }
        ImageCacheManager.shared.remove(for: postId, namespace: .originalImages)
        Task { await PostStore.shared.remove(postId: postId) }
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
            let filtered = uniquePosts(blockManager.filterBlocked(from: firstPage))
            postList.items = filtered
            currentPage = 0
            isLoadingFeed = false

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.feed_failed"
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
            let filtered = uniquePosts(blockManager.filterBlocked(from: firstPage))
            followingPostList.items = filtered
            currentFollowingPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.following_failed"
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

            let filtered = uniquePosts(blockManager.filterBlocked(from: next))
            followingPostList.items = mergeUniquePosts(existing: followingPostList.items, incoming: filtered)
            currentFollowingPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.following_page_failed"
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

            let filtered = uniquePosts(blockManager.filterBlocked(from: next))
            postList.items = mergeUniquePosts(existing: postList.items, incoming: filtered)
            currentPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.page_failed"
        }

        isLoadingFeed = false
    }

    func refreshFeed() async {
        do {
            let latest = try await FeedLoader.fetchPage(page: 0, pageSize: pageSize)
            let existing = Set(postList.items.map { $0.id })
            let newPosts = uniquePosts(blockManager.filterBlocked(from: latest))
                .filter { !existing.contains($0.id) }

            guard !newPosts.isEmpty else { return }
            postList.items.insert(contentsOf: newPosts, at: 0)
            postList.items = uniquePosts(postList.items)

            enqueueImages(for: newPosts)
        } catch {
            genLogKey = "content.genlog.refresh_failed"
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
            let filtered = uniquePosts(filterMyPosts(blockManager.filterBlocked(from: first)))
            myPostList.items = filtered
            currentMyPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.my_posts_failed"
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
            let filtered = uniquePosts(filterMyPosts(blockManager.filterBlocked(from: next)))
            myPostList.items = mergeUniquePosts(existing: myPostList.items, incoming: filtered)
            currentMyPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.my_posts_page_failed"
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
            let filtered = uniquePosts(blockManager.filterBlocked(from: first))
            likedPostList.items = filtered
            currentLikedPage = 0

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.liked_failed"
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
            let filtered = uniquePosts(blockManager.filterBlocked(from: next))
            likedPostList.items = mergeUniquePosts(existing: likedPostList.items, incoming: filtered)
            currentLikedPage += 1

            enqueueImages(for: filtered)
        } catch {
            genLogKey = "content.genlog.liked_page_failed"
        }
    }

    @MainActor
    func enqueueImages(for posts: [Post]) {
        guard !isGenerationSuspendedForPosting else { return }
        let canGenerate = canGenerateImagesNow
        let modelID = modelManager.activeImageGenerationCacheKey
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
                post.imageGenerationFailed = false
                post.imageGenerationFailureReason = nil
                scheduleRegenerationEvaluationUpdateIfNeeded(for: post, generatedImage: cached, modelID: modelID)
            } else {
                post.semanticFidelityScore = nil
                post.lpipsDistance = nil
                post.imageGenerationFailed = false
                post.imageGenerationFailureReason = nil
                if post.previewImage == nil {
                    post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
                }
                if post.localImage == nil,
                   canGenerate,
                   !generationQueue.contains(where: { $0.id == post.id }) {
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

        while !generationQueue.isEmpty {
            if isGenerationSuspendedForPosting { return }
            if Task.isCancelled { return }
            let post = generationQueue.removeFirst()
            guard let prompt = post.effectivePrompt else { continue }
            guard let backend = modelManager.resolvedImageGenerationBackend else { continue }
            if backend == .stableDiffusion && (!isGeneratorReady || generator == nil) {
                await maybeReloadGeneratorForSelectedModel()
                guard isGeneratorReady, generator != nil else {
                    generationQueue.insert(post, at: 0)
                    return
                }
            }
            let modelID = modelManager.activeImageGenerationCacheKey
            let rawInitImage = post.makeInitImage()
            let shouldDisableInitImage = backend == .stableDiffusion &&
                (modelManager.selectedSDModelID == ModelManager.sd15LCMModelID || forceSDTextToImage)
            let initImage: UIImage? = shouldDisableInitImage ? nil : rawInitImage
            let cacheKey = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
            let generationStart = Date()

            do {
                let img = try await generateImage(for: post, prompt: prompt, initImage: initImage, backend: backend)
                post.localImage = img
                post.previewImage = nil
                post.imageGenerationFailed = false
                post.imageGenerationFailureReason = nil
                ImageCacheManager.shared.save(img, for: cacheKey)
                ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
                scheduleRegenerationEvaluationUpdateIfNeeded(for: post, generatedImage: img, modelID: modelID)
                updateImageGenerationDiagnosticsIfNeeded(for: post, generationStart: generationStart, modelID: modelID)
            } catch {
                #if DEBUG
                print("⚠️ Image generation failed:", error)
                #endif
                updateImageGenerationDiagnosticsIfNeeded(for: post, generationStart: generationStart, modelID: modelID)
                post.previewImage = nil
                post.imageGenerationFailed = true
                post.imageGenerationFailureReason = localizedImageGenerationFailureReason(error: error, backend: backend)
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func generateImage(
        for post: Post,
        prompt: String,
        initImage: UIImage?,
        backend: ImageGenerationBackend
    ) async throws -> UIImage {
        switch backend {
        case .stableDiffusion:
            guard let generator else {
                throw NSError(
                    domain: "ContentView",
                    code: -41,
                    userInfo: [NSLocalizedDescriptionKey: "Stable Diffusion generator is not loaded."]
                )
            }

            let hasInit = (initImage != nil)
            let enhancedPrompt = hasInit
                ? "\(prompt), sharp focus, fine detail, highly detailed, crisp texture, high clarity"
                : prompt
            let negativePrompt = hasInit
                ? "blurry, soft focus, low detail, lowres, out of focus"
                : ""
            let profile = SDModeProfile.forMode(post.privacyMode, modelID: modelManager.selectedSDModelID)
            let seed = deterministicSeed(for: post, modelID: modelManager.selectedSDModelID, prompt: prompt)

            do {
                return try await generator.generateImage(
                    from: enhancedPrompt,
                    negativePrompt: negativePrompt,
                    initImage: initImage,
                    strength: profile.denoiseStrength,
                    steps: profile.stepCount,
                    guidance: profile.guidanceScale,
                    seed: seed
                )
            } catch {
                #if DEBUG
                print("⚠️ SD img2img failed, retrying with txt2img:", error)
                #endif
                return try await generator.generateImage(
                    from: enhancedPrompt,
                    negativePrompt: negativePrompt,
                    initImage: nil,
                    steps: profile.stepCount,
                    guidance: profile.guidanceScale,
                    seed: seed
                )
            }
        case .imagePlayground:
            return try await ImagePlaygroundGenerator.shared.generateImageIfAvailable(
                from: prompt,
                tags: post.tags,
                sourceImage: nil,
                styleOption: modelManager.selectedImagePlaygroundStyle
            )
        case .automatic:
            throw NSError(
                domain: "ContentView",
                code: -42,
                userInfo: [NSLocalizedDescriptionKey: "Image generation backend is unresolved."]
            )
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
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
        let modelID = modelManager.activeImageGenerationCacheKey
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

    private func uniquePosts(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.id).inserted }
    }

    private func mergeUniquePosts(existing: [Post], incoming: [Post]) -> [Post] {
        var merged = existing
        let existingIDs = Set(existing.map(\.id))
        merged.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
        return merged
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

        if !generationQueue.isEmpty, !isGenerating, canGenerateImagesNow {
            isGenerating = true
            generationTask = Task { await processQueue() }
        }
    }

    @MainActor
    private func regenerateImage(for postID: String, post explicitPost: Post? = nil) async {
        let post = explicitPost ?? allKnownPosts.first(where: { $0.id == postID })
        guard let post else { return }
        guard let prompt = post.effectivePrompt else { return }

        let modelID = modelManager.activeImageGenerationCacheKey
        let key = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
        ImageCacheManager.shared.remove(for: key)
        ImageCacheManager.shared.removeSemanticScore(for: semanticScoreKey(for: post, modelID: modelID))
        post.localImage = nil
        post.imageGenerationFailed = false
        post.imageGenerationFailureReason = nil
        post.clearRegenerationEvaluation()
        post.previewImage = post.hasImage
            ? post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
            : nil

        generationQueue.removeAll { $0.id == postID }
        generationQueue.insert(post, at: 0)

        if !isGenerating, canGenerateImagesNow {
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

    private func localizedImageGenerationFailureReason(
        error: Error,
        backend: ImageGenerationBackend
    ) -> String {
        let message = (error as NSError).localizedDescription
        let normalized = "\(message) \(String(describing: error))".lowercased()

        if backend == .imagePlayground {
            if normalized.contains("unsupportedlanguage") {
                return l("content.image_generation.unsupported_prompt")
            }

            if normalized.contains("person") || normalized.contains("people") {
                return l("content.image_generation.people_restricted")
            }

            if normalized.contains("unavailable") {
                return l("content.image_generation.unavailable")
            }

            return l("content.image_generation.prompt_failed")
        }

        return l("content.image_generation.failed")
    }

    private var canGenerateImagesNow: Bool {
        guard let backend = modelManager.resolvedImageGenerationBackend else {
            return false
        }
        switch backend {
        case .stableDiffusion:
            return isGeneratorReady && generator != nil
        case .imagePlayground:
            return true
        case .automatic:
            return false
        }
    }

    private func deterministicSeed(for post: Post, modelID: String, prompt: String) -> UInt32 {
        let key = generatedCacheKey(for: post, modelID: modelID, prompt: prompt)
        let digest = SHA256.hash(data: Data(key.utf8))
        let bytes = Array(digest.prefix(4))
        guard bytes.count == 4 else { return 0 }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }

    @MainActor
    private func scheduleRegenerationEvaluationUpdateIfNeeded(for post: Post, generatedImage: UIImage, modelID: String) {
        guard post.hasImage, isCurrentUsersPost(post) else {
            post.semanticFidelityScore = nil
            post.lpipsDistance = nil
            return
        }

        guard let originalImage = ImageCacheManager.shared.load(for: post.id, namespace: .originalImages) else {
            post.semanticFidelityScore = nil
            post.lpipsDistance = nil
            return
        }

        let evaluationKey = semanticScoreKey(for: post, modelID: modelID)
        if let cachedEvaluation = ImageCacheManager.shared.loadRegenerationEvaluation(for: evaluationKey) {
            post.regenerationEvaluation = cachedEvaluation
        }

        if post.regenerationEvaluation?.semanticScore != nil && post.regenerationEvaluation?.lpipsDistance != nil {
            return
        }

        guard !semanticScoreTasks.contains(evaluationKey) else { return }
        semanticScoreTasks.insert(evaluationKey)

        Task {
            let metrics = await computeRegenerationEvaluationMetrics(original: originalImage, regenerated: generatedImage)
            await MainActor.run {
                semanticScoreTasks.remove(evaluationKey)
                post.semanticFidelityScore = metrics.semanticScore
                post.lpipsDistance = metrics.lpipsDistance
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

    private func computeRegenerationEvaluationMetrics(
        original: UIImage,
        regenerated: UIImage
    ) async -> (semanticScore: Double?, lpipsDistance: Double?) {
        async let semanticScore = computeSemanticFidelityScore(original: original, regenerated: regenerated)
        async let lpipsDistance = computeLPIPSDistance(original: original, regenerated: regenerated)
        return await (semanticScore, lpipsDistance)
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

    private func computeLPIPSDistance(original: UIImage, regenerated: UIImage) async -> Double? {
        do {
            return try await LPIPSService.shared.evaluateDistance(original: original, generated: regenerated)
        } catch {
            #if DEBUG
            print("⚠️ LPIPS scoring failed:", error)
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
        let activeKey = modelManager.activeImageGenerationCacheKey

        if modelManager.resolvedImageGenerationBackend == .stableDiffusion {
            if deferStableDiffusionReloadUntilRestart {
                genLogKey = "content.genlog.sd_restart_required"
                return
            }
            guard loadedGenerationCacheKey != activeKey || generator == nil else { return }
            await reloadGeneratorForSelectedModel()
            return
        }

        deferStableDiffusionReloadUntilRestart = false
        generationTask?.cancel()
        generationTask = nil
        generationQueue.removeAll()
        isGenerating = false

        if let current = generator {
            await current.unloadResources()
            generator = nil
            isGeneratorReady = false
        }

        loadedGenerationCacheKey = activeKey
        genLogKey = "content.genlog.ready"
        try? await Task.sleep(nanoseconds: 250_000_000)
        enqueueImages(for: allKnownPosts)
    }

    @MainActor
    private func reloadGeneratorForSelectedModel() async {
        guard !isGenerationSuspendedForPosting else { return }
        let previousKey = loadedGenerationCacheKey

        generationTask?.cancel()
        generationTask = nil
        generationQueue.removeAll()
        isGenerating = false

        if let current = generator {
            await current.unloadResources()
            generator = nil
            isGeneratorReady = false
        }

        guard modelManager.resolvedImageGenerationBackend == .stableDiffusion else {
            loadedGenerationCacheKey = modelManager.activeImageGenerationCacheKey
            enqueueImages(for: allKnownPosts)
            return
        }

        do {
            let gen = try ImageGenerator(modelsDirectory: modelManager.selectedSDModelDirectory)
            generator = gen
            isGeneratorReady = true
            loadedGenerationCacheKey = modelManager.activeImageGenerationCacheKey
            genLogKey = "content.genlog.ready"

            try? await Task.sleep(nanoseconds: 250_000_000)
            enqueueImages(for: allKnownPosts)
        } catch {
            #if DEBUG
            print("❌ SD re-init failed:", error)
            #endif
            generator = nil
            isGeneratorReady = false
            loadedGenerationCacheKey = nil
            genLogKey = "content.genlog.model_switch_failed"
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

        genLogKey = "content.genlog.paused_during_posting"
    }

    @MainActor
    private func resumeImageGenerationAfterPosting() async {
        guard isGenerationSuspendedForPosting else { return }
        isGenerationSuspendedForPosting = false

        await maybeReloadGeneratorForSelectedModel()
        enqueueImages(for: allKnownPosts)
        if canGenerateImagesNow {
            genLogKey = "content.genlog.ready"
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
