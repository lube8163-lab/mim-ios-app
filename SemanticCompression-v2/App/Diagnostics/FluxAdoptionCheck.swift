#if DEBUG
import UIKit
import CryptoKit
import Darwin

/// Explicit device check through the shipping installer, VLM, recipe and renderer. No posts/accounts are used.
@MainActor
final class FluxAdoptionCheck {
    private let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MimFluxAdoption")
    private var record: [String: Any] = [:]
    private var maximumFootprint: UInt64 = 0
    private let update: (String) -> Void
    init(update: @escaping (String) -> Void) { self.update = update }
    func run() async {
        let manager = ModelManager.shared
        record = ["kind": "MimFluxAdoption", "startedAt": Date().ISO8601Format(), "uploadsUsed": false,
                  "osVersion": UIDevice.current.systemVersion, "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                  "thermalStateAtStart": ProcessInfo.processInfo.thermalState.rawValue]
        UIApplication.shared.isIdleTimerDisabled = true
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                maximumFootprint = max(maximumFootprint, Self.footprint())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        var renderTask: Task<PhotoGenerationOutput, Error>?
        defer { sampler.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let downloadRequired = !manager.isSDModelInstalled(ModelManager.fluxModelID)
            record["downloadRequired"] = downloadRequired
            if downloadRequired {
                let partial = ModelManager.modelsRoot.appendingPathComponent(CoreAIFluxAssets.installPath)
                    .appendingPathComponent("model.zip.part")
                record["resumedFromBytes"] = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                record["reusedCompleteArchiveBytes"] = (try? partial.deletingLastPathComponent()
                    .appendingPathComponent("model.zip").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                record["status"] = "downloading"; try save()
                let began = ProcessInfo.processInfo.systemUptime
                manager.installSD(modelID: ModelManager.fluxModelID)
                while manager.sdInstalling {
                    try await Task.sleep(for: .seconds(1))
                    record["downloadedBytes"] = manager.sdDownloadedBytes
                    record["totalBytes"] = manager.sdTotalBytes
                    try save(); update("FLUXを準備中: \(Int(manager.sdProgress * 100))%")
                    if ProcessInfo.processInfo.arguments.contains("--mim-flux-interrupt-download"), manager.sdDownloadedBytes >= 20_000_000 {
                        manager.cancelInstall()
                        while manager.sdInstalling { try await Task.sleep(for: .milliseconds(100)) }
                        let bytes = try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard bytes >= 20_000_000, bytes < CoreAIFluxAssets.archiveBytes else {
                            throw RecipeError.invalid("中断したダウンロードを保持できませんでした。")
                        }
                        record["partialBytesAfterCancellation"] = bytes
                        record["writesDrainedBeforeUnlock"] = !manager.assetWritesLocked
                        record["status"] = "completed-download-cancellation"; try save()
                        update("ダウンロードの中断・保持を確認済み"); return
                    }
                }
                guard manager.isSDModelInstalled(ModelManager.fluxModelID) else {
                    throw RecipeError.invalid(manager.statusMessage ?? "ダウンロードに失敗しました。")
                }
                record["downloadAndInstallationSeconds"] = ProcessInfo.processInfo.systemUptime - began
                record["downloadArchiveSHA256"] = CoreAIFluxAssets.archiveSHA256
            }
            let manifest = try await manager.manifest(for: ModelManager.fluxModelID)
            guard try manifest.identity == CoreAIFluxAssets.catalog().identity,
                  manager.selectedSDModelID == ModelManager.fluxModelID, manager.selectedGenerationProvider == .coreAI else {
                throw RecipeError.modelMismatch
            }
            record["manifestVerified"] = true
            record["modelManifest"] = try JSONSerialization.jsonObject(with: canonicalData(manifest))
            if ProcessInfo.processInfo.arguments.contains("--mim-flux-download-only") {
                record["status"] = "completed"; try save(); update("FLUXのダウンロード検証完了"); return
            }
            guard let source = UIImage(named: "OnboardingPhoto") else { throw RecipeError.invalid("作例がありません。") }
            record["status"] = "understanding"; try save(); update("VLMとの連携を確認中")
            let vision = try await SemanticExtractionTask.shared.describe(source, provider: .coreAIVLM)
            guard vision.identity.runtime == "CoreAI" else { throw RecipeError.invalid("CoreAI VLMで検証できませんでした。") }
            let prompt = try SceneRecipePrompt.build(vision.scene, manifest: manifest, resources: manager.directory(for: manifest))
            let recipe = GenerationRecipe.photo(prompt: prompt, manifest: manifest, safetyPolicyIdentity: try PromptPolicy.bundled().identity)
            try recipe.validate()
            record["recipe"] = try JSONSerialization.jsonObject(with: canonicalData(recipe))
            record["vlmSeconds"] = vision.measurements.elapsedSeconds ?? 0
            record["scene"] = try JSONSerialization.jsonObject(with: canonicalData(vision.scene))
            try save()
            let renderer = RecipeImageRenderer.shared
            record["status"] = "baseline"; try save(); update("FLUXの生成を確認中")
            record["thermalStateBeforeGeneration"] = ProcessInfo.processInfo.thermalState.rawValue
            let started = ProcessInfo.processInfo.systemUptime
            let baseline = try await renderer.renderMeasured(recipe, seed: 42)
            let baselineHash = try hash(baseline.image, name: "baseline.png")
            record["baselineSeconds"] = ProcessInfo.processInfo.systemUptime - started
            record["runtime"] = baseline.identity.runtime
            guard baseline.identity.runtime == "CoreAI" else { throw RecipeError.modelMismatch }
            record["status"] = "switching"; try save(); update("投稿と閲覧の切り替えを確認中")
            let beforeYield = renderer.completedYieldCount
            let resumed = Task { try await renderer.renderMeasured(recipe, seed: 42) }
            renderTask = resumed
            let deadline = ProcessInfo.processInfo.systemUptime + 90
            while renderer.currentFluxStep == 4 || renderer.currentFluxStep < 1 {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    resumed.cancel(); _ = try await resumed.value
                    throw RecipeError.invalid("生成の進行を確認できませんでした。")
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            try await Task.sleep(for: .milliseconds(500))
            let requested = ProcessInfo.processInfo.systemUptime
            let analysis = try await SemanticExtractionTask.shared.describe(source, provider: .coreAIVLM)
            let analysisFinished = ProcessInfo.processInfo.systemUptime
            let output = try await resumed.value
            renderTask = nil
            let resumedHash = try hash(output.image, name: "resumed.png")
            guard resumedHash == baselineHash, renderer.completedYieldCount > beforeYield else {
                throw RecipeError.invalid("途中再開の画像が一致しませんでした。")
            }
            record["switchRequestToAnalysisFinishedSeconds"] = analysisFinished - requested
            record["switchVLMSeconds"] = analysis.measurements.elapsedSeconds ?? 0
            record["switchQueueWaitSeconds"] = analysisFinished - requested - (analysis.measurements.elapsedSeconds ?? 0)
            record["switchRequestToImageFinishedSeconds"] = ProcessInfo.processInfo.systemUptime - requested
            record["identicalImageAfterResume"] = true
            record["imageSHA256"] = baselineHash
            record["yieldCount"] = renderer.completedYieldCount - beforeYield
            let defaults = UserDefaults(suiteName: "mim.flux-adoption." + UUID().uuidString)!
            let viewer = ViewerSeedStore(defaults: defaults, randomSeed: { 43 })
            let seed = try viewer.seed(for: recipe, postID: "offline-fixture")
            let secondStarted = ProcessInfo.processInfo.systemUptime
            let second = try await renderer.render(recipe, seed: seed)
            record["warmGenerationSeconds"] = ProcessInfo.processInfo.systemUptime - secondStarted
            record["viewerSeedChangesImage"] = try hash(second, name: "viewer-43.png") != baselineHash
            guard record["viewerSeedChangesImage"] as? Bool == true else { throw RecipeError.invalid("seedによる変化を確認できませんでした。") }
            await renderer.discardFluxCache()
            record["modelsReleased"] = !manager.isUnderstanding && !manager.isUsingModel
            record["status"] = "completed"
        } catch {
            renderTask?.cancel(); _ = try? await renderTask?.value
            record["status"] = "failed"; record["error"] = String(describing: error)
            await RecipeImageRenderer.shared.discardFluxCache()
        }
        record["finishedAt"] = Date().ISO8601Format()
        record["sampledMaximumPhysicalFootprintBytes"] = maximumFootprint
        record["memorySampleIntervalSeconds"] = 0.1
        record["thermalStateAtEnd"] = ProcessInfo.processInfo.thermalState.rawValue
        try? save(); update("実機検証: \(record["status"] ?? "unknown")")
    }
    private func hash(_ image: UIImage, name: String) throws -> String {
        // The renderer has already passed output safety before returning this image.
        guard let data = image.pngData() else { throw RecipeError.invalid("画像を保存できませんでした。") }
        try data.write(to: folder.appendingPathComponent(name))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func save() throws {
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("result.json"), options: .atomic)
    }
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
#endif
