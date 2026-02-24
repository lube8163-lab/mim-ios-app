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
        case myPosts
        case liked
        case profile
    }

    @State private var appBootState: AppBootState = .launching

    // MARK: - Core State

    @StateObject private var postList = PostList()
    @StateObject private var myPostList = PostList()
    @StateObject private var likedPostList = PostList()
    @StateObject private var blockManager = BlockManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @State private var showNewPost = false
    @State private var showInstallModels = false
    @State private var selectedTab: HomeTab = .timeline

    @State private var genLog = "Ready"
    @State private var isLoadingFeed = false
    @State private var isLoadingMyPosts = false
    @State private var isLoadingLikedPosts = false

    @State private var generator: ImageGenerator?
    @State private var isGeneratorReady = false

    // Pagination
    @State private var currentPage = 0
    @State private var currentMyPage = 0
    @State private var currentLikedPage = 0
    private let pageSize = 10
    @State private var hasLoadedMyPosts = false
    @State private var hasLoadedLikedPosts = false

    // Image generation queue
    @State private var generationQueue: [Post] = []
    @State private var isGenerating = false
    @State private var showReportToast = false
    @State private var showBlockToast = false
    @State private var showLoginSheet = false

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
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if showReportToast {
                    Text(t(ja: "通報を受け付けました。投稿を非表示にしました。", en: "Report submitted. The post was hidden."))
                        .toastStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showBlockToast {
                    Text(t(ja: "ユーザーをブロックしました。投稿を非表示にしました。", en: "User blocked. Posts were hidden."))
                        .toastStyle()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: showReportToast)
        .animation(.easeInOut(duration: 0.2), value: showBlockToast)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ZStack {
                    feedBody
                    floatingNewPostButton
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    timelineLogo
                }
            }
            .tabItem {
                Label(t(ja: "ホーム", en: "Home"), systemImage: "house")
            }
            .tag(HomeTab.timeline)

            NavigationStack {
                Group {
                    if authManager.isAuthenticated {
                        postsListContent(
                            posts: blockManager.filterBlocked(from: myPostList.items),
                            isLoading: isLoadingMyPosts,
                            emptyText: t(ja: "自分の投稿はまだありません", en: "No posts yet"),
                            onRefresh: loadMyPosts,
                            onLoadNext: loadNextMyPage
                        )
                    } else {
                        loginRequiredView(
                            title: t(ja: "投稿履歴を見るにはログイン", en: "Sign in to see your posts"),
                            description: t(ja: "この端末で投稿した履歴や下書きを管理できます。", en: "Manage your post history on this device.")
                        )
                    }
                }
                .navigationTitle(t(ja: "自分の投稿", en: "My Posts"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(t(ja: "投稿", en: "Posts"), systemImage: "person.text.rectangle")
            }
            .tag(HomeTab.myPosts)
            .task {
                guard !hasLoadedMyPosts else { return }
                await loadMyPosts()
            }

            NavigationStack {
                Group {
                    if authManager.isAuthenticated {
                        postsListContent(
                            posts: blockManager.filterBlocked(from: likedPostList.items),
                            isLoading: isLoadingLikedPosts,
                            emptyText: t(ja: "いいねした投稿はまだありません", en: "No liked posts yet"),
                            onRefresh: loadLikedPosts,
                            onLoadNext: loadNextLikedPage
                        )
                    } else {
                        loginRequiredView(
                            title: t(ja: "いいね履歴を見るにはログイン", en: "Sign in to see liked posts"),
                            description: t(ja: "気になった投稿を後から見返せます。", en: "Save and revisit posts you liked.")
                        )
                    }
                }
                .navigationTitle(t(ja: "いいね", en: "Liked"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(t(ja: "いいね", en: "Liked"), systemImage: "heart")
            }
            .tag(HomeTab.liked)
            .task {
                guard !hasLoadedLikedPosts else { return }
                await loadLikedPosts()
            }

            NavigationStack {
                UserProfileView(showsCloseButton: false)
            }
            .tabItem {
                Label(t(ja: "プロフィール", en: "Profile"), systemImage: "person.circle")
            }
            .tag(HomeTab.profile)
        }
        .sheet(isPresented: $showNewPost) {
            NewPostView(posts: $postList.items)
        }
        .sheet(isPresented: $showLoginSheet) {
            OTPLoginView(allowsSkip: true)
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
        }
        .onDisappear {
            Task { await generator?.unloadResources() }
        }
    }
}

extension ContentView {

    func bootSequence() async {
        genLog = t(ja: "準備完了", en: "Ready")

        // ユーザー登録
        let user = UserManager.shared.currentUser
        if !user.id.isEmpty {
            await UserService.register(user)
            await blockManager.refreshFromServerIfPossible()
        }

        // モデル未インストールなら即 ready
        guard modelManager.isModelInstalled else {
            appBootState = .ready
            await loadInitialPage()
            return
        }

        appBootState = .preparingModel

        // SD 初期化（ここで固まっても OK）
        let sdDir = ModelManager.modelsRoot
            .appendingPathComponent("StableDiffusion/sd15")

        do {
            let gen = try ImageGenerator(modelsDirectory: sdDir)
            self.generator = gen
            self.isGeneratorReady = true
        } catch {
            #if DEBUG
            print("❌ SD init failed:", error)
            #endif
            self.generator = nil
            self.isGeneratorReady = false
        }

        appBootState = .ready
        await loadInitialPage()
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
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        }
                        ForEach(postList.items) { post in
                            PostCardView(
                                post: post,
                                isModelInstalled: modelManager.isModelInstalled,
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
                    .padding(.vertical, 12)
                }
                .refreshable {
                    await refreshFeed()
                }
            }

            Divider()
            bottomStatusBar
        }
    }
}

extension ContentView {

    private var bottomStatusBar: some View {
        Group {
            if modelManager.isModelInstalled {
                Text(genLog)
            } else {
                Text(t(ja: "⚠️ モデル未インストール（画像生成は無効）", en: "⚠️ Model not installed (image generation disabled)"))
                    .foregroundColor(.orange)
            }
        }
        .font(.footnote)
        .foregroundColor(.gray)
        .padding(.bottom, 6)
    }

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
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 56))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .shadow(radius: 3)
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
                .padding(.bottom, 24)
            }
        }
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

    private var guestLoginBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t(ja: "ゲスト閲覧中", en: "Browsing as Guest"))
                .font(.subheadline.weight(.bold))
            Text(
                t(
                    ja: "投稿・いいね・ブロックはログイン後に利用できます。",
                    en: "Posting, likes, and block controls are available after sign-in."
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            Button {
                showLoginSheet = true
            } label: {
                Text(t(ja: "メールでログイン", en: "Sign in with Email"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            isModelInstalled: modelManager.isModelInstalled,
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
                .padding(.vertical, 12)
            }
            .refreshable {
                await onRefresh()
            }
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
    }

    private func removeBlockedUserFromLists(_ blockedUserId: String) {
        postList.items.removeAll { $0.userId == blockedUserId }
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
        myPostList.items.removeAll { $0.id == postId }
        likedPostList.items.removeAll { $0.id == postId }
        showReportToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            showReportToast = false
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
        let userId = UserManager.shared.currentUser.id
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
            let userId = UserManager.shared.currentUser.id
            myPostList.items = blockManager.filterBlocked(from: postList.items.filter { $0.userId == userId })
        }
    }

    func loadNextMyPage() async {
        guard !isLoadingMyPosts else { return }
        let userId = UserManager.shared.currentUser.id
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
        let userId = UserManager.shared.currentUser.id
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
        let userId = UserManager.shared.currentUser.id
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
        let canGenerate = modelManager.isModelInstalled
        for post in posts {
            guard post.hasImage else {
                post.previewImage = nil
                continue
            }
            let cacheKey = post.effectivePrompt.map { "\(post.mode)::\($0)" }
            if let cacheKey,
               let cached = ImageCacheManager.shared.load(for: cacheKey) {
                post.localImage = cached
            } else {
                if post.previewImage == nil {
                    post.previewImage = post.makePreviewImage(targetSize: CGSize(width: 32, height: 32))
                }
                if canGenerate, !generationQueue.contains(where: { $0.id == post.id }) {
                    generationQueue.append(post)
                }
            }
        }

        guard canGenerate else { return }
        guard !isGenerating else { return }
        isGenerating = true
        Task { await processQueue() }
    }

    @MainActor
    func processQueue() async {
        guard let generator else {
            isGenerating = false
            return
        }

        while !generationQueue.isEmpty {
            let post = generationQueue.removeFirst()
            guard let prompt = post.effectivePrompt else { continue }
            let initImage = post.makeInitImage()
            let hasInit = (initImage != nil)
            let enhancedPrompt = hasInit
                ? "\(prompt), sharp focus, fine detail, highly detailed, crisp texture, high clarity"
                : prompt
            let negativePrompt = hasInit
                ? "blurry, soft focus, low detail, lowres, out of focus"
                : ""
            let profile = SDModeProfile.forMode(post.privacyMode)

            do {
                let img = try await generator.generateImage(
                    from: enhancedPrompt,
                    negativePrompt: negativePrompt,
                    initImage: initImage,
                    strength: profile.denoiseStrength,
                    guidance: profile.guidanceScale
                )
                post.localImage = img
                post.previewImage = nil
                ImageCacheManager.shared.save(img, for: "\(post.mode)::\(prompt)")
            } catch {
                #if DEBUG
                print("⚠️ Image generation failed:", error)
                #endif
                do {
                    let fallback = try await generator.generateImage(
                        from: enhancedPrompt,
                        negativePrompt: negativePrompt,
                        initImage: nil,
                        guidance: profile.guidanceScale
                    )
                    post.localImage = fallback
                    post.previewImage = nil
                    ImageCacheManager.shared.save(fallback, for: "\(post.mode)::\(prompt)")
                } catch {
                    #if DEBUG
                    print("⚠️ Fallback generation failed:", error)
                    #endif
                    post.previewImage = nil
                }
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        isGenerating = false
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
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
