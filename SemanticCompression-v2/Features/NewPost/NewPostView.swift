import SwiftUI
import PhotosUI
import Combine
import CryptoKit
import Darwin

@MainActor
final class PhotoComposer: ObservableObject {
    enum Phase { case idle, reading, understanding, preparing, reconstructing, ready, uploading, failed, cancelling, cancelled }
    @Published var image: UIImage?
    @Published var preview: UIImage?
    @Published var scene: PhotoSceneDescription?
    private var extractedScene: PhotoSceneDescription?
    @Published var prompt = ""
    @Published var userText = ""
    @Published var phase: Phase = .idle
    @Published var message: String?
    @Published var recipe: GenerationRecipe?
    @Published var seed = UInt32.random(in: 0...UInt32.max)
    @Published var sourceSHA256: String?
    @Published var understandingSeconds: Double?
    @Published var processedSize: CGSize?
    @Published private(set) var understandingEvidence: UnderstandingStageEvidence?
    @Published private(set) var generationEvidence: GenerationStageEvidence?
    private var caseID = UUID().uuidString
    private var operation: Task<Void, Never>?
    private var operationID = UUID()
    var busy: Bool { [.reading, .understanding, .preparing, .reconstructing, .uploading, .cancelling].contains(phase) }
    var canPost: Bool { phase != .reading && phase != .uploading && phase != .cancelling && (image != nil || !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var phaseLabel: String {
        switch phase {
        case .reading: return "写真を読み込み中"
        case .understanding: return "写真を理解中"
        case .preparing: return "再現の準備中"
        case .reconstructing: return "写真を再現中"
        case .uploading: return "投稿中"
        case .ready: return "再現を確認できます"
        case .failed: return "完了できませんでした"
        case .cancelled: return "中止しました"
        case .cancelling: return "処理を中止中"
        case .idle: return ""
        }
    }
    func cancel() {
        guard phase != .uploading else { return }
        if let operation, busy { phase = .cancelling; operation.cancel() }
        else { operation = nil; phase = .cancelled }
    }
    func invalidatePreview() { recipe = nil; preview = nil; generationEvidence = nil; if !busy { phase = .idle } }
    func invalidateUnderstanding() {
        guard !busy else { return }
        scene = nil; extractedScene = nil; prompt = ""; understandingEvidence = nil
        understandingSeconds = nil; processedSize = nil; invalidatePreview()
    }
    func load(_ item: PhotosPickerItem) {
        cancel()
        image = nil; scene = nil; prompt = ""; invalidatePreview(); message = nil
        extractedScene = nil; sourceSHA256 = nil; understandingSeconds = nil; processedSize = nil
        understandingEvidence = nil; generationEvidence = nil; caseID = UUID().uuidString
        let id = UUID(); operationID = id; phase = .reading
        operation = Task {
            defer { finishOperation(id) }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let loaded = UIImage(data: data) else {
                    throw RecipeError.invalid("写真を読み込めませんでした。")
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                image = loaded
                sourceSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                phase = .idle
            } catch {
                guard operationID == id else { return }
                if Task.isCancelled { phase = .cancelled }
                else { phase = .failed; message = error.localizedDescription }
            }
        }
    }
    func prepare() {
        guard let image, !busy else { return }
        message = nil
        recipe = nil; preview = nil
        let id = UUID(); operationID = id
        phase = scene == nil ? .understanding : .preparing
        operation = Task {
            defer { finishOperation(id) }
            do {
                generationEvidence = pendingGeneration()
                try ModelManager.shared.generationProviderAvailability.requireReady()
                if scene == nil {
                    phase = .understanding
                    startUnderstandingEvidence()
                    let extracted = try await SemanticExtractionTask.shared.describe(image, provider: ModelManager.shared.selectedUnderstandingProvider)
                    try Task.checkCancellation()
                    guard operationID == id else { return }
                    acceptUnderstanding(extracted)
                }
                phase = .preparing
                let manifest = try await ModelManager.shared.manifest(for: ModelManager.shared.selectedSDModelID)
                try Task.checkCancellation()
                let policy = try PromptPolicy.bundled()
                if let scene, prompt == scene.generationPrompt {
                    prompt = try SceneRecipePrompt.build(scene, manifest: manifest,
                        resources: ModelManager.shared.directory(for: manifest))
                }
                try policy.validate(prompt: prompt)
                let value = GenerationRecipe.photo(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    manifest: manifest, safetyPolicyIdentity: try policy.identity)
                try value.validate()
                phase = .reconstructing
                generationEvidence = try generationRecord(recipe: value)
                let generated = try await PhotoProviderRegistry.generation(ModelManager.shared.selectedGenerationProvider).render(value, seed: seed)
                try Task.checkCancellation()
                guard operationID == id else { return }
                recipe = value; preview = generated.image; phase = .ready
                generationEvidence?.status = .completed
                generationEvidence?.measurements = generated.measurements
                generationEvidence?.result = .init(imageSHA256: generated.image.pngData().map {
                    SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
                })
            } catch {
                guard operationID == id else { return }
                markUnfinishedEvidence(cancelled: error is CancellationError || Task.isCancelled)
                if error is CancellationError || Task.isCancelled { phase = .cancelled }
                else { phase = .failed; message = error.localizedDescription }
            }
        }
    }
    func describeOnly() {
        guard let image, !busy else { return }
        recipe = nil; preview = nil; message = nil
        scene = nil; extractedScene = nil; understandingSeconds = nil; processedSize = nil
        understandingEvidence = nil; generationEvidence = nil
        let id = UUID(); operationID = id; phase = .understanding
        operation = Task {
            defer { finishOperation(id) }
            do {
                startUnderstandingEvidence()
                let extracted = try await SemanticExtractionTask.shared.describe(image, provider: ModelManager.shared.selectedUnderstandingProvider)
                try Task.checkCancellation()
                guard operationID == id else { return }
                acceptUnderstanding(extracted)
                phase = .idle
            } catch {
                guard operationID == id else { return }
                markUnfinishedEvidence(cancelled: error is CancellationError || Task.isCancelled)
                phase = error is CancellationError || Task.isCancelled ? .cancelled : .failed
                if phase == .failed { message = error.localizedDescription }
            }
        }
    }
    func removePhoto() {
        cancel(); operationID = UUID(); operation = nil
        image = nil; scene = nil; prompt = ""; recipe = nil; preview = nil; message = nil
        extractedScene = nil; sourceSHA256 = nil; understandingSeconds = nil; processedSize = nil; phase = .idle
        understandingEvidence = nil; generationEvidence = nil
        seed = UInt32.random(in: .min ... .max)
    }
    func prepareNewVariation() {
        guard !busy else { return }
        let previous = seed
        seed = UInt32.random(in: .min ... .max)
        if seed == previous { seed &+= 1 }
        prepare()
    }
    private func finishOperation(_ id: UUID) {
        guard operationID == id else { return }
        operation = nil
        if phase == .cancelling { phase = .cancelled }
    }
    func exportComparison() throws -> URL {
        guard !busy, let sourceSHA256 else {
            throw RecipeError.invalid("写真の読み込みが必要です。")
        }
        let value = PhotoComparisonRecord(version: 2, sourceID: caseID,
                                          understandingBackend: actualUnderstandingBackend,
                                          sourceSHA256: sourceSHA256, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                          deviceModel: Self.machineIdentifier(), processedWidth: processedSize.map { Int($0.width) },
                                          processedHeight: processedSize.map { Int($0.height) }, understandingElapsedSeconds: understandingSeconds,
                                          scene: extractedScene, recipe: recipe, editedPrompt: prompt,
                                          understandingRecord: currentUnderstandingRecord(),
                                          generationRecord: generationEvidence ?? pendingGeneration())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mim-comparison-\(UUID().uuidString).json")
        try canonicalData(value).write(to: url, options: .atomic)
        return url
    }
    private var environment: StageEnvironment {
        #if targetEnvironment(simulator)
        let target: StageEnvironment.Target = .simulator
        #else
        let target: StageEnvironment.Target = .physicalDevice
        #endif
        return .init(deviceModel: Self.machineIdentifier(), osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                     executionTarget: target)
    }
    private func startUnderstandingEvidence() {
        let provider = PhotoProviderRegistry.understanding(ModelManager.shared.selectedUnderstandingProvider)
        understandingEvidence = .init(stage: .understanding, caseID: caseID, status: .notRun,
            sourceSHA256: sourceSHA256 ?? "", identity: provider.identity, environment: environment, measurements: .init(),
            input: .init(processedWidth: nil, processedHeight: nil, preprocessingVersion: "notRun", processedSHA256: nil,
                         instructionVersion: "photo-scene-v2"),
            result: .init(prompt: nil, caption: nil, observations: nil, uncertainties: nil, editedPrompt: nil),
            recordedAt: Date().ISO8601Format())
        if provider.availability.canRun { understandingEvidence?.status = .failed }
    }
    private func acceptUnderstanding(_ output: PhotoUnderstandingOutput) {
        let extracted = output.scene
        scene = extracted; extractedScene = extracted; prompt = extracted.generationPrompt
        understandingSeconds = output.measurements.elapsedSeconds; processedSize = output.processedSize
        understandingEvidence = .init(stage: .understanding, caseID: caseID, status: .completed,
            sourceSHA256: sourceSHA256 ?? "", identity: output.identity, environment: environment, measurements: output.measurements,
            input: .init(processedWidth: Int(output.processedSize.width), processedHeight: Int(output.processedSize.height),
                         preprocessingVersion: "uiimage-orientation-max1536-v1", processedSHA256: nil, instructionVersion: "photo-scene-v2"),
            result: .init(prompt: extracted.generationPrompt, caption: extracted.description,
                          observations: extracted.subjects + [extracted.counts, extracted.arrangement, extracted.relationships,
                              extracted.colors, extracted.lighting, extracted.background, extracted.medium],
                          uncertainties: nil, editedPrompt: nil), recordedAt: Date().ISO8601Format())
        understandingEvidence?.fallbackReason = output.fallbackReason
        understandingEvidence?.requestedUnderstandingProvider = ModelManager.shared.selectedUnderstandingProvider
    }
    var actualUnderstandingBackend: String {
        understandingEvidence?.identity.runtime == "CoreAI" ? UnderstandingProviderID.coreAIVLM.rawValue : UnderstandingProviderID.foundationModels.rawValue
    }
    private func currentUnderstandingRecord() -> UnderstandingStageEvidence? {
        var record = understandingEvidence
        record?.result.editedPrompt = prompt == extractedScene?.generationPrompt ? nil : prompt
        return record
    }
    private func pendingGeneration() -> GenerationStageEvidence {
        let manager = ModelManager.shared
        let identity: StageModelIdentity = manager.selectedGenerationProvider == .coreAI ? .unconfiguredCoreAI :
            .init(modelID: manager.selectedSDModelID, modelRevision: manager.selectedSDModel?.revision,
                  runtime: "CoreML", runtimeVersion: nil, assetManifestSHA256: nil)
        return .init(stage: .generation, caseID: caseID, status: .notRun, sourceSHA256: sourceSHA256 ?? "",
            identity: identity, environment: environment, measurements: .init(),
            input: .init(prompt: prompt, negativePrompt: "", promptSource: promptSource, understandingRecordSHA256: nil),
            result: .init(imageSHA256: nil), recordedAt: Date().ISO8601Format())
    }
    private var promptSource: GenerationEvidenceInput.PromptSource {
        guard let extractedScene else { return .manual }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines) == extractedScene.generationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            ? .rawUnderstanding : .editedUnderstanding
    }
    private func generationRecord(recipe: GenerationRecipe) throws -> GenerationStageEvidence {
        let record = currentUnderstandingRecord()
        return .init(stage: .generation, caseID: caseID, status: .failed, sourceSHA256: sourceSHA256 ?? "",
            identity: try .generation(recipe.model), environment: environment, measurements: .init(),
            input: .init(prompt: recipe.prompt, negativePrompt: recipe.negativePrompt, promptSource: promptSource,
                         understandingRecordSHA256: try record.map { try canonicalDigest($0) }),
            result: .init(imageSHA256: nil), settings: .init(seed: seed, width: recipe.width, height: recipe.height,
                scheduler: recipe.scheduler, steps: recipe.steps, guidance: recipe.guidance, pipelineVersion: recipe.pipelineVersion),
            recordedAt: Date().ISO8601Format())
    }
    private func markUnfinishedEvidence(cancelled: Bool) {
        if understandingEvidence?.status == .failed && cancelled { understandingEvidence?.status = .cancelled }
        if generationEvidence?.status == .failed && cancelled { generationEvidence?.status = .cancelled }
    }
    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

typealias PhotoComparisonRecord = MimComparisonRecord<PhotoSceneDescription>

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var posts: [Post]
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var modelManager: ModelManager
    @StateObject private var composer = PhotoComposer()
    @State private var item: PhotosPickerItem?
    @State private var previewSelection = 0
    @State private var showSettings = false
    @State private var exportURL: URL?
    @State private var uploadTask: Task<Void, Never>?
    @State private var uncertainUpload = false

    private var comparisonMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-model-comparison")
        #else
        false
        #endif
    }
    var body: some View {
        let changePhotoTitle = mt("写真を変更")
        let addPhotoTitle = mt("写真を追加")
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        CachedAvatarView(urlString: UserManager.shared.currentUser.avatarUrl) {
                            Circle().fill(MimStyle.soft)
                                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                        }.clipShape(Circle())
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ContentSafetyPolicy.displayText(UserManager.shared.currentUser.displayName)).font(.subheadline.weight(.semibold))
                            TextField(mt("いま、何してる？"), text: $composer.userText, axis: .vertical)
                                .font(.body).lineLimit(3...12)
                                .accessibilityIdentifier("post-text-field")
                                .onChange(of: composer.userText) { _, text in
                                    if text.count > 300 { composer.userText = String(text.prefix(300)) }
                                }
                                .disabled(composer.phase == .uploading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        if let original = composer.image {
                            Image(uiImage: original).resizable().scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(mt("選択した写真"))
                            HStack {
                                PhotosPicker(selection: $item, matching: .images, preferredItemEncoding: .current) {
                                    Text(changePhotoTitle).frame(minHeight: 44)
                                }
                                Spacer()
                                Button(role: .destructive) { item = nil; composer.removePhoto() } label: {
                                    Text(mt("削除")).frame(minHeight: 44)
                                }
                            }.font(.subheadline).disabled(composer.phase == .uploading)
                            Text(mt("写真は投稿後に処理されます。"))
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            PhotosPicker(selection: $item, matching: .images, preferredItemEncoding: .current) {
                                Label(addPhotoTitle, systemImage: "photo")
                                    .font(.body).frame(minHeight: 44)
                            }.disabled(composer.busy)
                        }
                        if composer.phase == .reading { ProgressView(mt("写真を読み込み中")) }
                        if comparisonMode, composer.image != nil {
                            DisclosureGroup("モデル比較") {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let scene = composer.scene {
                                        Text(scene.description).font(.callout)
                                        TextField(mt("再現に使う説明"), text: $composer.prompt, axis: .vertical).lineLimit(3...8)
                                    }
                                    if let image = composer.preview { Image(uiImage: image).resizable().scaledToFit() }
                                    if composer.busy {
                                        ProgressView(mt(composer.phaseLabel))
                                        Button(mt("中止")) { composer.cancel() }
                                    } else {
                                        Button(mt("写真の説明を作成")) { composer.describeOnly() }
                                        Button(mt("再現を確認")) { composer.prepare() }
                                    }
                                    if let exportURL { ShareLink(item: exportURL) { Text(mt("比較データ")) } }
                                }.padding(.top, 12)
                            }
                        }
                        if let message = composer.message {
                            Text(mt(message)).font(.callout).foregroundStyle(.red)
                                .accessibilityIdentifier("composer-error")
                        }
                    }.padding(.leading, 48)
                }.padding(16)
            }
            .background(MimStyle.paper)
            .navigationTitle(mt("投稿"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { composer.cancel(); close() } label: {
                        Text(mt("キャンセル")).font(.subheadline)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }.buttonStyle(.plain).frame(minHeight: 44)
                        .disabled(composer.phase == .uploading)
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button { submit() } label: {
                        Text(mt("投稿")).font(.subheadline.weight(.semibold))
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(composer.canPost && !uncertainUpload ? .white : Color.secondary)
                            .padding(.horizontal, 20).frame(minHeight: 44)
                            .background(composer.canPost && !uncertainUpload ? MimStyle.accent : MimStyle.soft, in: Capsule())
                    }.buttonStyle(.plain).disabled(!composer.canPost || uncertainUpload)
                        .accessibilityIdentifier("submit-post-button")
                }.sharedBackgroundVisibility(.hidden)
            }
            .interactiveDismissDisabled(composer.phase == .uploading)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--mim-ui-review"),
               ProcessInfo.processInfo.arguments.contains("--mim-ui-review-photo") {
                composer.image = UIReviewFixtures.photo()
            }
            #endif
        }
        .onChange(of: item) { _, next in if let next { composer.load(next) } }
        .onChange(of: composer.prompt) { _, _ in if !composer.busy { composer.invalidatePreview() } }
        .onChange(of: modelManager.selectedUnderstandingProvider) { _, _ in composer.invalidateUnderstanding() }
        .onChange(of: modelManager.selectedGenerationProvider) { _, _ in composer.invalidatePreview() }
        .onChange(of: modelManager.selectedSDModelID) { _, _ in composer.cancel(); composer.invalidatePreview() }
        .onChange(of: composer.recipe) { _, _ in refreshComparisonExport() }
        .onChange(of: composer.scene) { _, _ in refreshComparisonExport() }
        .onChange(of: composer.phase) { _, _ in refreshComparisonExport() }
        .onDisappear { composer.cancel() }
    }

    private func refreshComparisonExport() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mim-model-comparison") {
            exportURL = try? composer.exportComparison()
        }
        #endif
    }

    private func sceneLabel(_ key: String) -> String {
        ["subjects": "主題", "counts": "個数", "arrangement": "配置", "relationships": "関係", "colors": "色",
         "lighting": "光", "background": "背景", "medium": "画風"][key] ?? key
    }
    private func sceneValue(_ key: String) -> String {
        guard let scene = composer.scene else { return "" }
        switch key {
        case "subjects": return scene.subjects.joined(separator: ", ")
        case "counts": return scene.counts
        case "arrangement": return scene.arrangement
        case "relationships": return scene.relationships
        case "colors": return scene.colors
        case "lighting": return scene.lighting
        case "background": return scene.background
        default: return scene.medium
        }
    }
    private func submit() {
        guard composer.canPost else { return }
        composer.cancel()
        composer.phase = .uploading; composer.message = nil
        let image = composer.image
        let text = composer.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        uploadTask = Task {
            do {
                try ContentSafetyPolicy.bundled().validate(text)
                let post: Post
                if let image {
                    // Persist the work before dismissing; analysis belongs to the app's queue.
                    post = try await BackgroundPhotoPosts.shared.submit(image: image, text: text)
                } else {
                    let user = UserManager.shared.currentUser
                    let value = Post(id: UUID().uuidString, userId: user.id, displayName: user.displayName,
                        avatarUrl: user.avatarUrl, userText: text, hasImage: false, status: .completed)
                    let result = try await PostUploader().upload(post: value)
                    value.id = result.id
                    post = await PostStore.shared.resolve(value)
                }
                if !posts.contains(where: { $0.id == post.id }) { posts.insert(post, at: 0) }
                composer.phase = .ready
                composer.removePhoto(); composer.userText = ""; item = nil
                close()
            } catch {
                composer.phase = .failed; composer.message = error.localizedDescription
                uncertainUpload = image == nil && ((error as? PostUploadError)?.postMayHaveBeenSaved ?? false)
            }
        }
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
}
