#if DEBUG
import SwiftUI
import CryptoKit

/// Explicitly launched local diagnostics. No account, photo-library access, or uploads.
@MainActor
struct DeviceGenerationSmokeView: View {
    @State private var status = "実機確認を開始します"
    @State private var images: [UIImage] = []
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MiM 実機確認").font(.title)
                Text(status).font(.body).textSelection(.enabled)
                ForEach(images.indices, id: \.self) { index in
                    Image(uiImage: images[index]).resizable().scaledToFit()
                }
            }.padding()
        }
        .task {
            guard !started else { return }
            started = true
            await run()
        }
    }

    private func run() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        let downloadVLM = ProcessInfo.processInfo.arguments.contains("--mim-vlm-download")
        let afmBaseline = ProcessInfo.processInfo.arguments.contains("--mim-afm-baseline")
        let understandingOnly = ProcessInfo.processInfo.arguments.contains("--mim-understanding-only")
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(afmBaseline ? "MimDeviceSmokeAFM" : downloadVLM ? "MimDeviceSmokeCoreAI" : "MimDeviceSmoke", isDirectory: true)
        var record: [String: Any] = [
            "kind": "MimDeviceSmoke", "recordedAt": Date().ISO8601Format(),
            "osVersion": UIDevice.current.systemVersion,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "coreAIAvailability": CoreAIPhotoUnderstandingService.availability.status.rawValue,
            "coreAIMessage": CoreAIPhotoUnderstandingService.availability.message,
            "peakMemoryMeasured": false
        ]
        func save() throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("result.json"), options: .atomic)
        }
        func update(_ message: String) {
            status = message
            print("MIM_DEVICE_SMOKE: \(message)")
        }
        do {
            try save()
            if downloadVLM {
                update("Cloudflareから写真理解モデルを準備しています")
                let manager = ModelManager.shared
                manager.installUnderstandingModel()
                while manager.sdInstalling {
                    try await Task.sleep(for: .milliseconds(500))
                }
                try CoreAIPhotoUnderstandingService.availability.requireReady()
                record["coreAIAvailability"] = CoreAIPhotoUnderstandingService.availability.status.rawValue
                record["coreAIMessage"] = CoreAIPhotoUnderstandingService.availability.message
                record["cloudflareModelInstalled"] = true
                try save()
            }
            let input = referenceGraphic()
            try input.pngData()?.write(to: folder.appendingPathComponent("understanding-input.png"), options: .atomic)
            update("写真理解モデルを確認しています")
            var inputs: [(String, UIImage)] = [("reference-graphic", input)]
            let fixtures = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MimVLMTestImages")
            for name in ["two-apples.png", "one-apple.png"] {
                if let image = UIImage(contentsOfFile: fixtures.appendingPathComponent(name).path) { inputs.append((name, image)) }
            }
            var understandingResults: [[String: Any]] = []
            for (name, image) in inputs {
                do {
                    let provider = PhotoProviderRegistry.understanding(afmBaseline ? .foundationModels : .coreAIVLM)
                    let output = try await provider.analyze(image)
                    let result: [String: Any] = [
                        "case": name, "status": "completed", "runtime": output.identity.runtime,
                        "modelID": output.identity.modelID, "fallbackReason": output.fallbackReason ?? "",
                        "prompt": output.scene.generationPrompt, "description": output.scene.description,
                        "subjects": output.scene.subjects, "counts": output.scene.counts,
                        "elapsedSeconds": output.measurements.elapsedSeconds ?? 0,
                        "preparationSeconds": output.measurements.preparationSeconds ?? 0,
                        "inferenceSeconds": output.measurements.inferenceSeconds ?? 0,
                        "elapsedScope": output.measurements.elapsedScope ?? ""
                    ]
                    understandingResults.append(result)
                    if name == "reference-graphic" {
                        record["coreAIPrimaryVerified"] = output.identity.runtime == "CoreAI"
                        record["understanding"] = result
                    }
                } catch {
                    let result = ["case": name, "status": "failed", "error": error.localizedDescription]
                    understandingResults.append(result)
                    if name == "reference-graphic" { record["understanding"] = result }
                }
                record["understandingCases"] = understandingResults
                try save()
            }
            if understandingOnly {
                update("写真理解の確認が完了しました。結果はDocuments/\(folder.lastPathComponent)に保存しました。")
                return
            }
            try save()
            update("再現モデルを検証しています")
            let manager = ModelManager.shared
            manager.reloadState()
            let manifest = try await manager.manifest(for: ModelManager.sd15ModelID)
            let policy = try PromptPolicy.bundled()
            let recipe = GenerationRecipe(version: 2,
                prompt: "A studio photograph of a red apple and a blue ceramic cup on a wooden table, soft daylight, simple light background.",
                negativePrompt: "", model: manifest, pipelineVersion: GenerationRecipe.pipelineVersion,
                promptFormatVersion: GenerationRecipe.promptFormatVersion, safetyPolicyIdentity: try policy.identity,
                seed: nil, width: manifest.width, height: manifest.height, scheduler: "dpmSolverMultistep",
                steps: 25, guidance: 7.5, seedPolicy: .viewerRandom)
            let store = ViewerSeedStore.shared
            let postID = "debug-device-smoke-sd15-v2"
            let firstSeed = try store.seed(for: recipe, postID: postID)
            let secondSeed = try store.seed(for: recipe, postID: postID, replacing: true)
            let reopenedSeed = try ViewerSeedStore(defaults: .standard).seed(for: recipe, postID: postID)
            guard let wire = try JSONSerialization.jsonObject(with: canonicalData(recipe)) as? [String: Any] else {
                throw RecipeError.invalid("投稿レシピを確認できません。")
            }
            record["recipeVersion"] = recipe.version
            record["sharedRecipeHasSeed"] = wire["seed"] != nil
            record["localSeedPersists"] = reopenedSeed == secondSeed
            record["cacheKeysDiffer"] = try recipe.renderCacheKey(seed: firstSeed) != recipe.renderCacheKey(seed: secondSeed)
            record["assetManifestSHA256"] = try manifest.identity
            var results: [[String: Any]] = []
            for (index, seed) in [firstSeed, secondSeed].enumerated() {
                update("異なるseedで画像を生成しています（\(index + 1)/2）")
                let output = try await PhotoProviderRegistry.generation(.coreML).render(recipe, seed: seed)
                guard let png = output.image.pngData() else { throw RecipeError.invalid("PNGを保存できません。") }
                let file = "generation-\(index + 1).png"
                try png.write(to: folder.appendingPathComponent(file), options: .atomic)
                images.append(output.image)
                results.append([
                    "seed": seed, "runtime": output.identity.runtime, "modelID": output.identity.modelID,
                    "file": file, "width": Int(output.image.size.width), "height": Int(output.image.size.height),
                    "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
                    "elapsedSeconds": output.measurements.elapsedSeconds ?? 0,
                    "inferenceSeconds": output.measurements.inferenceSeconds ?? 0
                ])
                record["generations"] = results
                try save()
            }
            record["imagesDiffer"] = (results[0]["sha256"] as? String) != (results[1]["sha256"] as? String)
            record["generationStatus"] = "completed"
            try save()
            update("画像生成の確認が完了しました。結果はDocuments/\(folder.lastPathComponent)に保存しました。")
        } catch {
            record["generationStatus"] = "failed"
            record["generationError"] = error.localizedDescription
            try? save()
            update("実機確認: \(error.localizedDescription)")
        }
    }

    private func referenceGraphic() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: .init(width: 512, height: 512), format: format).image { context in
            UIColor.white.setFill()
            context.fill(.init(x: 0, y: 0, width: 512, height: 512))
            UIColor.systemRed.setFill()
            context.cgContext.fillEllipse(in: .init(x: 60, y: 160, width: 160, height: 160))
            UIColor.systemBlue.setFill()
            context.fill(.init(x: 300, y: 160, width: 160, height: 160))
        }
    }
}
#endif
