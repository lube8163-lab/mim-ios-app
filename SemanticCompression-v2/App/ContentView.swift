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
                postsListContent(
                    posts: blockManager.filterBlocked(from: myPostList.items),
                    isLoading: isLoadingMyPosts,
                    emptyText: t(ja: "自分の投稿はまだありません", en: "No posts yet"),
                    onRefresh: loadMyPosts,
                    onLoadNext: loadNextMyPage
                )
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
                postsListContent(
                    posts: blockManager.filterBlocked(from: likedPostList.items),
                    isLoading: isLoadingLikedPosts,
                    emptyText: t(ja: "いいねした投稿はまだありません", en: "No liked posts yet"),
                    onRefresh: loadLikedPosts,
                    onLoadNext: loadNextLikedPage
                )
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
        await UserService.register(user)
        await blockManager.refreshFromServerIfPossible()

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
                Button(action: { showNewPost = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(radius: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var timelineLogo: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 22)
                .accessibilityHidden(true)
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
            postList.items = blockManager.filterBlocked(from: firstPage)
            currentPage = 0
            isLoadingFeed = false

            if modelManager.isModelInstalled {
                enqueueImages(for: firstPage)
            }
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

            postList.items.append(contentsOf: blockManager.filterBlocked(from: next))
            currentPage += 1

            if modelManager.isModelInstalled {
                enqueueImages(for: next)
            }
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

            if modelManager.isModelInstalled {
                enqueueImages(for: newPosts)
            }
        } catch {
            genLog = t(ja: "⚠️ 更新に失敗", en: "⚠️ Refresh failed")
        }
    }

    func loadMyPosts() async {
        guard !isLoadingMyPosts else { return }
        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }
        hasLoadedMyPosts = true

        do {
            let userId = UserManager.shared.currentUser.id
            let first = try await FeedLoader.fetchMyPosts(
                userId: userId,
                page: 0,
                pageSize: pageSize
            )
            myPostList.items = blockManager.filterBlocked(from: first)
            currentMyPage = 0

            if modelManager.isModelInstalled {
                enqueueImages(for: first)
            }
        } catch {
            genLog = t(ja: "⚠️ 自分の投稿の読み込みに失敗", en: "⚠️ Failed to load my posts")
            let userId = UserManager.shared.currentUser.id
            myPostList.items = blockManager.filterBlocked(from: postList.items.filter { $0.userId == userId })
        }
    }

    func loadNextMyPage() async {
        guard !isLoadingMyPosts else { return }
        isLoadingMyPosts = true
        defer { isLoadingMyPosts = false }

        do {
            let userId = UserManager.shared.currentUser.id
            let next = try await FeedLoader.fetchMyPosts(
                userId: userId,
                page: currentMyPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else { return }
            myPostList.items.append(contentsOf: blockManager.filterBlocked(from: next))
            currentMyPage += 1

            if modelManager.isModelInstalled {
                enqueueImages(for: next)
            }
        } catch {
            genLog = t(ja: "⚠️ 自分の投稿ページ読み込みに失敗", en: "⚠️ Failed to load my posts page")
        }
    }

    func loadLikedPosts() async {
        guard !isLoadingLikedPosts else { return }
        isLoadingLikedPosts = true
        defer { isLoadingLikedPosts = false }
        hasLoadedLikedPosts = true

        do {
            let userId = UserManager.shared.currentUser.id
            let first = try await FeedLoader.fetchLikedPosts(
                userId: userId,
                page: 0,
                pageSize: pageSize
            )
            likedPostList.items = blockManager.filterBlocked(from: first)
            currentLikedPage = 0

            if modelManager.isModelInstalled {
                enqueueImages(for: first)
            }
        } catch {
            genLog = t(ja: "⚠️ いいね投稿の読み込みに失敗", en: "⚠️ Failed to load liked posts")
            likedPostList.items = blockManager.filterBlocked(from: postList.items.filter { $0.isLikedByCurrentUser == true })
        }
    }

    func loadNextLikedPage() async {
        guard !isLoadingLikedPosts else { return }
        isLoadingLikedPosts = true
        defer { isLoadingLikedPosts = false }

        do {
            let userId = UserManager.shared.currentUser.id
            let next = try await FeedLoader.fetchLikedPosts(
                userId: userId,
                page: currentLikedPage + 1,
                pageSize: pageSize
            )
            guard !next.isEmpty else { return }
            likedPostList.items.append(contentsOf: blockManager.filterBlocked(from: next))
            currentLikedPage += 1

            if modelManager.isModelInstalled {
                enqueueImages(for: next)
            }
        } catch {
            genLog = t(ja: "⚠️ いいね投稿ページ読み込みに失敗", en: "⚠️ Failed to load liked posts page")
        }
    }

    @MainActor
    func enqueueImages(for posts: [Post]) {
        for post in posts {
            if let prompt = post.semanticPrompt,
               let cached = ImageCacheManager.shared.load(for: prompt) {
                post.localImage = cached
            } else {
                if !generationQueue.contains(where: { $0.id == post.id }) {
                    generationQueue.append(post)
                }
            }
        }

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
            guard let prompt = post.semanticPrompt else { continue }

            do {
                let img = try await generator.generateImage(from: prompt)
                post.localImage = img
                ImageCacheManager.shared.save(img, for: prompt)
            } catch {
                #if DEBUG
                print("⚠️ Image generation failed:", error)
                #endif
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
