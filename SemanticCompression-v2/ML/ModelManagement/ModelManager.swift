import Combine
import Foundation

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()
    static let sd15ModelID = "sd15"
    static let sanaSprintModelID = "sana_sprint"
    static let sdxlModelID = "sdxl-local"
    static let fluxModelID = CoreAIFluxAssets.modelID

    nonisolated struct SDModelConfig: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let revision: String
        let family: PipelineFamily
        let installPath: String
        let sizeLabel: String
        let downloadURL: URL?
        let sha256: String?
        let width: Int
    }
    static let supportedSDModels: [SDModelConfig] = [
        .init(id: fluxModelID, title: "FLUX.2 Klein 4B", revision: CoreAIFluxAssets.revision, family: .flux2Klein4B,
              installPath: CoreAIFluxAssets.installPath, sizeLabel: "約4 GB · 512px",
              downloadURL: CoreAIFluxAssets.fragments.first?.url, sha256: CoreAIFluxAssets.archiveSHA256, width: 512),
        .init(id: sd15ModelID, title: "Stable Diffusion 1.5", revision: "coreml-v2", family: .sd15,
              installPath: "StableDiffusion/sd15", sizeLabel: "約2 GB",
              downloadURL: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sd15/sd15_coreml_v2.zip"),
              sha256: "37e4f91b81ac501a9ef7f30ccbc216367de4f5a14a963441fc6ee8abce16e7ed", width: 512),
        .init(id: sanaSprintModelID, title: "Sana Sprint 0.6B", revision: "coreml-v1", family: .sanaSprint06B,
              installPath: "StableDiffusion/sana_sprint", sizeLabel: "約2.3 GB",
              downloadURL: URL(string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sana/sana_sprint_coreml_v1.zip"),
              sha256: "06d6e68494337115b5e2923c9f46715f1a4ad1011e493207d105ad1194523429", width: 512),
        .init(id: sdxlModelID, title: "SDXL Core ML（比較用）", revision: "local-import-v1", family: .sdxl,
              installPath: "StableDiffusion/sdxl-local", sizeLabel: "ローカル資産を取り込み",
              downloadURL: nil, sha256: nil, width: 1024)
    ]
    @Published var selectedSDModelID: String
    @Published private(set) var selectedUnderstandingProvider: UnderstandingProviderID = .coreAIVLM
    @Published private(set) var selectedGenerationProvider: GenerationProviderID = .coreAI
    @Published private(set) var isUnderstanding = false
    @Published var sdInstalled = false
    @Published var sdInstalling = false
    @Published var sdProgress: Double = 0
    @Published var sdDownloadedBytes: Int64 = 0
    @Published var sdTotalBytes: Int64 = 0
    @Published var statusMessage: String?
    @Published var understandingAvailability = FoundationPhotoUnderstandingService.availability
    private var installer: ModelInstaller?
    private var subscriptions = Set<AnyCancellable>()
    private var verifiedAssets: [String: (fingerprint: String, manifest: ModelAssetManifest)] = [:]
    private var verificationTasks: [String: Task<(String, ModelAssetManifest), Error>] = [:]
    @Published private(set) var isUsingModel = false
    private var waitingUnderstandingCount = 0
    private var yieldCurrentGeneration: (() -> Void)?
    @Published private var verificationCount = 0
    var assetWritesLocked: Bool { sdInstalling || isUsingModel || isUnderstanding || waitingUnderstandingCount > 0 || verificationCount > 0 }

    func beginUnderstanding() throws {
        guard !isUnderstanding, !isUsingModel else { throw RecipeError.invalid("写真の処理中です。") }
        isUnderstanding = true
    }
    func endUnderstanding() { isUnderstanding = false }
    func beginUnderstandingWhenAvailable() async throws {
        waitingUnderstandingCount += 1
        defer { waitingUnderstandingCount -= 1 }
        yieldCurrentGeneration?()
        while sdInstalling || isUsingModel || isUnderstanding {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        try beginUnderstanding()
    }
    func setGenerationYieldHandler(_ action: (() -> Void)?) {
        yieldCurrentGeneration = action
        if waitingUnderstandingCount > 0 { action?() }
    }
    func selectUnderstandingProvider(_ value: UnderstandingProviderID) {
        guard !assetWritesLocked else { return }
        selectedUnderstandingProvider = value
        UserDefaults.standard.set(value.rawValue, forKey: "mim_understanding_provider_v1")
        reloadState()
    }
    func selectGenerationProvider(_ value: GenerationProviderID) {
        guard !assetWritesLocked else { return }
        selectedGenerationProvider = value
        UserDefaults.standard.set(value.rawValue, forKey: "mim_generation_provider_v1")
        reloadState()
    }

    func beginModelUse() throws {
        guard !sdInstalling, !isUsingModel, !isUnderstanding else { throw RecipeError.invalid("モデルの準備が終わるまでお待ちください。") }
        isUsingModel = true
    }
    func endModelUse() { isUsingModel = false }
    func beginModelUseWhenAvailable() async throws {
        // A submitted photo gets the next free slot before additional feed images.
        // Keep the two large models from loading together on memory-limited phones.
        while sdInstalling || isUsingModel || isUnderstanding || waitingUnderstandingCount > 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        try beginModelUse()
    }

    var sdModels: [SDModelConfig] { Self.supportedSDModels }
    var selectedSDModel: SDModelConfig? { sdModels.first { $0.id == selectedSDModelID } }
    var understandingProviderAvailability: ProviderAvailability {
        PhotoProviderRegistry.understanding(selectedUnderstandingProvider).availability
    }
    var generationProviderAvailability: ProviderAvailability {
        PhotoProviderRegistry.generation(selectedGenerationProvider).availability
    }
    var canGenerateImages: Bool { generationProviderAvailability.canRun }
    var canUnderstandImages: Bool { understandingProviderAvailability.canRun }
    static var modelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Models")
    }
    var selectedSDModelDirectory: URL? {
        selectedSDModel.map { Self.modelsRoot.appendingPathComponent($0.installPath) }
    }
    init() {
        selectedSDModelID = Self.fluxModelID
        selectedUnderstandingProvider = .coreAIVLM
        selectedGenerationProvider = .coreAI
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mim-model-comparison") {
            selectedSDModelID = UserDefaults.standard.string(forKey: AppPreferences.selectedSDModelKey) ?? Self.fluxModelID
            selectedUnderstandingProvider = UnderstandingProviderID(rawValue: UserDefaults.standard.string(forKey: "mim_understanding_provider_v1") ?? "") ?? .coreAIVLM
            selectedGenerationProvider = GenerationProviderID(rawValue: UserDefaults.standard.string(forKey: "mim_generation_provider_v1") ?? "") ?? .coreAI
        }
        #endif
        reloadState()
    }
    func reloadState() {
        understandingAvailability = FoundationPhotoUnderstandingService.availability
        sdInstalled = isSDModelInstalled(selectedSDModelID)
    }
    func selectSDModel(id: String) {
        guard !assetWritesLocked, sdModels.contains(where: { $0.id == id }) else { return }
        selectedSDModelID = id
        UserDefaults.standard.set(id, forKey: AppPreferences.selectedSDModelKey)
        reloadState()
    }
    func isSDModelInstalled(_ id: String) -> Bool {
        guard let config = sdModels.first(where: { $0.id == id }) else { return false }
        let root = Self.modelsRoot.appendingPathComponent(config.installPath)
        return ModelAssets.requiredFilesExist(at: root, family: config.family)
    }
    func manifest(for id: String) async throws -> ModelAssetManifest {
        guard !sdInstalling, let config = sdModels.first(where: { $0.id == id }), isSDModelInstalled(id) else {
            throw RecipeError.unsupported("再現モデルの準備が必要です。設定から準備してください。")
        }
        verificationCount += 1
        defer { verificationCount -= 1 }
        let root = Self.modelsRoot.appendingPathComponent(config.installPath)
        let fingerprint = try await Task.detached(priority: .utility) { try ModelAssets.inventoryFingerprint(at: root) }.value
        try Task.checkCancellation()
        if let existing = verifiedAssets[id], existing.fingerprint == fingerprint { return existing.manifest }
        if let pending = verificationTasks[id] {
            let result = try await pending.value.1
            try Task.checkCancellation()
            return result
        }
        let task = Task.detached(priority: .userInitiated) {
            let width = try ModelAssets.inspectedImageWidth(at: root, family: config.family)
            if config.family != .sdxl && width != config.width { throw RecipeError.modelMismatch }
            let manifest = try ModelAssets.manifest(at: root, modelID: config.id, revision: config.revision,
                                     family: config.family, width: width)
            if config.family == .flux2Klein4B {
                guard try manifest.identity == CoreAIFluxAssets.catalog().identity else { throw RecipeError.modelMismatch }
            }
            guard fingerprint == (try ModelAssets.inventoryFingerprint(at: root)) else {
                throw RecipeError.invalid("検証中にモデル資産が変更されました。再試行してください。")
            }
            return (fingerprint, manifest)
        }
        verificationTasks[id] = task
        defer { verificationTasks[id] = nil }
        let checked = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        verifiedAssets[id] = checked
        try Task.checkCancellation()
        return checked.1
    }
    /// Posting needs the identity of the downloadable model, not its multi-GB weights.
    /// Viewers still validate every installed file before rendering the recipe.
    func recipeManifest(for id: String) async throws -> ModelAssetManifest {
        if id == Self.fluxModelID { return try CoreAIFluxAssets.catalog() }
        if isSDModelInstalled(id) { return try await manifest(for: id) }
        guard id == Self.sd15ModelID,
              let url = Bundle.main.url(forResource: "sd15-catalog-manifest", withExtension: "json") else {
            throw RecipeError.unsupported("再現モデルの準備が必要です。")
        }
        let value = try JSONDecoder().decode(ModelAssetManifest.self, from: Data(contentsOf: url))
        try value.validate()
        guard value.modelID == id, value.revision == selectedSDModel?.revision, value.family == .sd15 else {
            throw RecipeError.modelMismatch
        }
        return value
    }
    func directory(for manifest: ModelAssetManifest) throws -> URL {
        guard let config = sdModels.first(where: { $0.id == manifest.modelID }),
              config.family == manifest.family, config.revision == manifest.revision,
              isSDModelInstalled(config.id) else { throw RecipeError.modelMismatch }
        return Self.modelsRoot.appendingPathComponent(config.installPath)
    }
    func installSD(modelID: String) {
        if modelID == Self.fluxModelID && !CoreAIFluxAssets.runtimeSupported {
            statusMessage = "画像の再現にはiOS 27.0.1以降・RAM 8 GB以上の対応端末が必要です。"; return
        }
        guard !assetWritesLocked, !isSDModelInstalled(modelID), let config = sdModels.first(where: { $0.id == modelID }),
              let url = config.downloadURL, let hash = config.sha256 else { return }
        statusMessage = nil
        verifiedAssets.removeAll()
        sdInstalling = true
        sdProgress = 0
        subscriptions.removeAll()
        let next = ModelInstaller(modelURL: url, modelName: config.installPath, expectedSHA256: hash,
            fragments: config.family == .flux2Klein4B ? CoreAIFluxAssets.fragments : nil, generationFamily: config.family)
        installer = next
        next.$progress.sink { [weak self] in self?.sdProgress = $0 }.store(in: &subscriptions)
        next.$downloadedBytes.sink { [weak self] in self?.sdDownloadedBytes = $0 }.store(in: &subscriptions)
        next.$totalBytes.sink { [weak self] in self?.sdTotalBytes = $0 }.store(in: &subscriptions)
        next.$status.sink { [weak self, weak next] state in
            guard let self else { return }
            switch state {
            case .completed:
                if let verified = next?.validatedGenerationAssets { self.verifiedAssets[modelID] = verified }
                self.sdInstalling = false
                self.reloadState()
                self.statusMessage = self.isSDModelInstalled(modelID) ? "準備が完了しました" : "モデル資産が不足しています"
            case .failed(let message): self.sdInstalling = false; self.statusMessage = message
            case .cancelled: self.sdInstalling = false; self.statusMessage = "準備を中止しました"
            default: break
            }
        }.store(in: &subscriptions)
        next.start()
    }
    func installUnderstandingModel() {
        guard !assetWritesLocked, !CoreAIVisionAssets.installed(at: CoreAIPhotoUnderstandingService.root),
              CoreAIPhotoUnderstandingService.availability.status != .unsupportedRuntime,
              let first = CoreAIVisionAssets.fragments.first else { return }
        statusMessage = nil
        sdInstalling = true
        sdProgress = 0; sdDownloadedBytes = 0; sdTotalBytes = 0
        subscriptions.removeAll()
        let next = ModelInstaller(modelURL: first.url, modelName: CoreAIVisionAssets.installPath,
            expectedSHA256: CoreAIVisionAssets.archiveSHA256, fragments: CoreAIVisionAssets.fragments, coreAIVision: true)
        installer = next
        next.$progress.sink { [weak self] in self?.sdProgress = $0 }.store(in: &subscriptions)
        next.$downloadedBytes.sink { [weak self] in self?.sdDownloadedBytes = $0 }.store(in: &subscriptions)
        next.$totalBytes.sink { [weak self] in self?.sdTotalBytes = $0 }.store(in: &subscriptions)
        next.$status.sink { [weak self] state in
            guard let self else { return }
            switch state {
            case .completed: self.sdInstalling = false; self.reloadState(); self.statusMessage = "準備が完了しました"
            case .failed(let message): self.sdInstalling = false; self.statusMessage = message
            case .cancelled: self.sdInstalling = false; self.statusMessage = "準備を中止しました"
            default: break
            }
        }.store(in: &subscriptions)
        next.start()
    }
    func cancelInstall() { installer?.cancel() }
    func importSDXL(from source: URL) async throws {
        guard !assetWritesLocked else { throw RecipeError.invalid("モデルの処理中です。完了後に再試行してください。") }
        sdInstalling = true
        defer { sdInstalling = false; reloadState() }
        let accessible = source.startAccessingSecurityScopedResource()
        defer { if accessible { source.stopAccessingSecurityScopedResource() } }
        guard let config = sdModels.first(where: { $0.id == Self.sdxlModelID }) else { throw RecipeError.modelMismatch }
        let destination = Self.modelsRoot.appendingPathComponent(config.installPath)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RecipeError.invalid("SDXL資産は既にあります。既存資産の上書きは行いません。")
        }
        let manifest = try await Task.detached(priority: .userInitiated) {
            let width = try ModelAssets.inspectedImageWidth(at: source, family: .sdxl)
            return try ModelAssets.manifest(at: source, modelID: config.id, revision: config.revision, family: .sdxl, width: width)
        }.value
        try manifest.validate()
        try Task.checkCancellation()
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".sdxl-import-" + UUID().uuidString)
        let task = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            try Task.checkCancellation()
            try fm.copyItem(at: source, to: staging)
            let copied = try ModelAssets.manifest(at: staging, modelID: config.id, revision: config.revision,
                                                 family: config.family, width: manifest.width)
            guard copied == manifest else { throw RecipeError.modelMismatch }
            try Task.checkCancellation()
            try fm.moveItem(at: staging, to: destination)
        }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        verifiedAssets.removeAll()
        statusMessage = "SDXL資産を取り込みました。実機の品質・メモリは未検証です。"
    }
}
