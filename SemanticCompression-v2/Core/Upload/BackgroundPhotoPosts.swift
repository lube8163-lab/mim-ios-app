import Combine
import Foundation
import UIKit

extension Notification.Name {
    static let backgroundPhotoPostUpdated = Notification.Name("backgroundPhotoPostUpdated")
}

@MainActor
final class BackgroundPhotoPosts: ObservableObject {
    static let shared = BackgroundPhotoPosts()
    @Published private(set) var isProcessing = false
    @Published private(set) var jobs: [PhotoPostPreparation] = []
    private var operation: Task<Void, Never>?
    private var pendingSubmission: (id: String, task: Task<PostUploadResponse, Error>)?
    private var deletingIDs = Set<String>()
    private var active = false
    private var analyzing = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingPhotoPosts", isDirectory: true)
        if let data = try? Data(contentsOf: self.root.appendingPathComponent("queue.json")),
           let saved = try? JSONDecoder().decode([PhotoPostPreparation].self, from: data) { jobs = saved }
    }

    func submit(image: UIImage, text: String) async throws -> Post {
        try ContentSafetyPolicy.bundled().validate(text)
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { throw CancellationError() }
        #endif
        let user = UserManager.shared.currentUser
        guard AuthManager.shared.isAuthenticated, !user.id.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let job = PhotoPostPreparation(id: UUID().uuidString, ownerID: user.id, displayName: user.displayName,
                                       avatarURL: user.avatarUrl, userText: text, createdAt: Date())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                              attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var directory = root
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        let bytes = try await Task.detached(priority: .utility) {
            try autoreleasepool {
                guard let bytes = Self.normalized(image).pngData() else { throw RecipeError.invalid("写真を保存できませんでした。") }
                return bytes
            }
        }.value
        try checkSession(user.id)
        try bytes.write(to: imageURL(job.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        jobs.append(job)
        do { try persist() }
        catch { jobs.removeAll { $0.id == job.id }; try? FileManager.default.removeItem(at: imageURL(job.id)); throw error }
        let post = await PostStore.shared.resolve(localPost(job))
        try checkOwner(job)
        resume()
        return post
    }

    func setActive(_ value: Bool) {
        active = value
        if value { resume() }
        // GPU inference must pause when the OS backgrounds this build. Network work can finish
        // under its finite UIKit background assertion; unfinished jobs resume on return.
        else if analyzing { operation?.cancel() }
    }
    func accountChanged() {
        active = false
        operation?.cancel()
    }
    func resume() {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { return }
        #endif
        guard active, operation == nil, AuthManager.shared.isAuthenticated,
              jobs.contains(where: { $0.ownerID == UserManager.shared.currentUser.id && $0.stage != .failed && !deletingIDs.contains($0.id) }) else { return }
        isProcessing = true
        operation = Task(priority: .utility) { [self] in
            defer {
                operation = nil; isProcessing = false
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
                }
                // A post can be added while the previous snapshot is being processed.
                // Resume also advances past a deleted job or an account change.
                resume()
            }
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Photo post") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    active = false
                    operation?.cancel()
                    if backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                        backgroundTask = .invalid
                    }
                }
            }
            let candidates = jobs.filter { $0.ownerID == UserManager.shared.currentUser.id && $0.stage != .failed && !deletingIDs.contains($0.id) }
            for value in candidates {
                guard !Task.isCancelled, let index = jobs.firstIndex(where: { $0.id == value.id }),
                      UserManager.shared.currentUser.id == value.ownerID else { break }
                do { try await process(jobs[index]) }
                catch is CancellationError { break }
                catch {
                    if Task.isCancelled { break }
                    guard AuthManager.shared.isAuthenticated,
                          UserManager.shared.currentUser.id == value.ownerID else { break }
                    guard let index = jobs.firstIndex(where: { $0.id == value.id }) else { continue }
                    jobs[index].stage = .failed; jobs[index].message = error.localizedDescription
                    let failed = jobs[index]
                    try? persist()
                    await publish(failed)
                    if failed.accepted, jobs.contains(where: { $0.id == failed.id }) {
                        try? await markFailed(id: failed.id, ownerID: failed.ownerID)
                    }
                }
            }
        }
    }
    func retry(_ id: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.ownerID == UserManager.shared.currentUser.id }) else { return }
        jobs[index].retry(); try? persist()
        let job = jobs[index]
        Task { await publish(job); resume() }
    }
    func remove(_ id: String) {
        if jobs.contains(where: { $0.id == id }) { operation?.cancel() }
        jobs.removeAll { $0.id == id }; try? persist()
        try? FileManager.default.removeItem(at: imageURL(id))
    }
    /// Let an already-sent create request settle before deleting its placeholder.
    /// Cancelling its transport alone cannot tell us whether the server committed it.
    func deletePendingPost(_ id: String) async throws -> Bool {
        guard let job = jobs.first(where: { $0.id == id && $0.ownerID == UserManager.shared.currentUser.id }) else { return false }
        deletingIDs.insert(id)
        defer { deletingIDs.remove(id); resume() }
        operation?.cancel()
        let submission = pendingSubmission.flatMap { $0.id == id ? $0.task : nil }
        if let submission { _ = try? await submission.value }
        try checkSession(job.ownerID)
        if job.accepted || submission != nil {
            // Another client may already have removed this queued placeholder.
            try await PostActionService.deletePost(postId: id, allowMissing: true)
        }
        remove(id)
        return true
    }
    func localPosts() async -> [Post] {
        var result: [Post] = []
        for job in jobs where job.ownerID == UserManager.shared.currentUser.id {
            result.append(await PostStore.shared.resolve(localPost(job)))
        }
        return result
    }
    private func localPost(_ job: PhotoPostPreparation) -> Post {
        let post = Post(id: job.id, userId: job.ownerID, displayName: job.displayName, avatarUrl: job.avatarURL,
                        caption: job.caption, semanticPrompt: job.recipe?.prompt, imageUnderstandingBackend: job.understandingBackend,
                        recipe: job.recipe, tags: job.tags, userText: job.userText, hasImage: true,
                        status: job.stage == .failed ? .failed : .pending, createdAt: job.createdAt)
        post.localPreparationMessage = job.message ?? (job.accepted ? "写真を処理中" : "投稿を送信中")
        return post
    }
    private func process(_ original: PhotoPostPreparation) async throws {
        var job = original
        try checkOwner(job)
        if !job.accepted {
            let capabilities = try await serverCapabilities()
            guard capabilities.backgroundPhotoPosts == true else { throw RecipeError.unsupported("投稿先の更新が必要です。") }
            try checkOwner(job)
            let submission = Task<PostUploadResponse, Error> {
                try await self.send(path: "/post", body: job.pendingPayload, ownerID: job.ownerID)
            }
            pendingSubmission = (job.id, submission)
            defer { pendingSubmission = nil }
            let result = try await submission.value
            try checkOwner(job)
            guard result.ok, result.id == job.id else { throw RecipeError.invalid("投稿の保存を確認できませんでした。") }
            job.accepted = true; job.stage = .accepted
            try store(job); await publish(job)
        }
        try Task.checkCancellation()
        try checkOwner(job)
        if job.recipe == nil {
            guard active else { throw CancellationError() }
            let manager = ModelManager.shared
            while manager.sdInstalling {
                try await Task.sleep(for: .milliseconds(100))
            }
            try checkOwner(job)
            guard active else { throw CancellationError() }
            if CoreAIPhotoUnderstandingService.availability.status == .missingAssets {
                while manager.assetWritesLocked {
                    try await Task.sleep(for: .milliseconds(100))
                    try checkOwner(job)
                    guard active else { throw CancellationError() }
                }
                job.message = "写真の説明用モデルを準備中"
                try store(job); await publish(job)
                manager.installUnderstandingModel()
                while manager.sdInstalling {
                    try await Task.sleep(for: .milliseconds(250))
                    try checkOwner(job)
                    guard active else { throw CancellationError() }
                }
            }
            guard let image = UIImage(contentsOfFile: imageURL(job.id).path) else {
                throw RecipeError.invalid("処理待ちの写真を読み込めませんでした。")
            }
            job.message = "写真の説明を作成中"
            try store(job); await publish(job)
            analyzing = true
            defer { analyzing = false }
            let output = try await SemanticExtractionTask.shared.describe(image, provider: manager.selectedUnderstandingProvider)
            analyzing = false
            try Task.checkCancellation()
            let manifest = try await manager.recipeManifest(for: manager.selectedSDModelID)
            let policy = try PromptPolicy.bundled()
            let prompt = try SceneRecipePrompt.build(output.scene, manifest: manifest,
                resources: manager.isSDModelInstalled(manifest.modelID) ? manager.directory(for: manifest) : nil)
            try policy.validate(prompt: prompt)
            let recipe = GenerationRecipe.photo(prompt: prompt, manifest: manifest, safetyPolicyIdentity: try policy.identity)
            try recipe.validate()
            job.caption = output.scene.description; job.tags = Array(output.scene.subjects.prefix(16))
            job.understandingBackend = output.identity.runtime == "CoreAI" ? "coreAIVLM" : "foundationModels"
            job.recipe = recipe; job.stage = .described
            try store(job)
        }
        try Task.checkCancellation()
        try checkOwner(job)
        guard let recipe = job.recipe else { throw RecipeError.invalid("写真の説明を作成できませんでした。") }
        let payload = CompletePhotoPostPayload(id: job.id, caption: job.caption, semanticPrompt: recipe.prompt,
                                              tags: job.tags, imageUnderstandingBackend: job.understandingBackend, recipe: recipe)
        let contentPolicy = try ContentSafetyPolicy.bundled()
        try contentPolicy.validate(job.userText)
        try contentPolicy.validate(job.caption)
        try contentPolicy.validate(job.tags.joined(separator: " "))
        try contentPolicy.validate(recipe.prompt, context: .generationPrompt)
        let result: PostUploadResponse = try await send(path: "/postPreparation", body: payload, ownerID: job.ownerID)
        guard result.ok, result.id == job.id, result.recipeDigest == (try canonicalDigest(recipe)) else {
            throw RecipeError.invalid("写真の処理結果の保存を確認できませんでした。")
        }
        try Task.checkCancellation()
        try checkOwner(job)
        let post = localPost(job); post.status = .completed; post.localPreparationMessage = nil
        let resolved = await PostStore.shared.resolve(post)
        try checkOwner(job)
        jobs.removeAll { $0.id == job.id }; try persist()
        try? FileManager.default.removeItem(at: imageURL(job.id))
        NotificationCenter.default.post(name: .backgroundPhotoPostUpdated, object: resolved)
    }
    private func store(_ job: PhotoPostPreparation) throws {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { throw CancellationError() }
        jobs[index] = job; try persist()
    }
    private func checkOwner(_ job: PhotoPostPreparation) throws {
        guard AuthManager.shared.isAuthenticated, UserManager.shared.currentUser.id == job.ownerID,
              jobs.contains(where: { $0.id == job.id }), !deletingIDs.contains(job.id) else { throw CancellationError() }
    }
    private func publish(_ job: PhotoPostPreparation) async {
        guard AuthManager.shared.isAuthenticated, UserManager.shared.currentUser.id == job.ownerID else { return }
        let post = await PostStore.shared.resolve(localPost(job))
        NotificationCenter.default.post(name: .backgroundPhotoPostUpdated, object: post)
    }
    private func persist() throws {
        try canonicalData(jobs).write(to: root.appendingPathComponent("queue.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func imageURL(_ id: String) -> URL { root.appendingPathComponent(id + ".png") }
    private func serverCapabilities() async throws -> RecipeServerCapabilities {
        let (data, response) = try await URLSession.shared.data(from: URL(string: FeedAPI.base + "/capabilities")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(RecipeServerCapabilities.self, from: data)
    }
    private func send<T: Encodable, R: Decodable>(path: String, body: T, ownerID: String) async throws -> R {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { throw CancellationError() }
        #endif
        try checkSession(ownerID)
        var request = try await AuthManager.shared.authorizedRequest(url: URL(string: FeedAPI.base + path)!, method: "POST")
        try checkSession(ownerID)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("mim-prompt-only-v2", forHTTPHeaderField: "X-Mim-Post-Format")
        request.httpBody = try canonicalData(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkSession(ownerID)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: data)
    }
    private func checkSession(_ ownerID: String) throws {
        try Task.checkCancellation()
        guard AuthManager.shared.isAuthenticated, UserManager.shared.currentUser.id == ownerID else { throw CancellationError() }
    }
    private func markFailed(id: String, ownerID: String) async throws {
        struct Failure: Encodable { let id: String; let status = "failed" }
        struct Receipt: Decodable { let ok: Bool }
        let _: Receipt = try await send(path: "/postPreparation", body: Failure(id: id), ownerID: ownerID)
    }
    nonisolated private static func normalized(_ image: UIImage) -> UIImage {
        let scale = min(1, 1536 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
