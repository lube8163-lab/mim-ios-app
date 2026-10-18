import SwiftUI
import UniformTypeIdentifiers

struct ModelManagementView: View {
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    @EnvironmentObject private var modelManager: ModelManager
    @State private var importing = false
    private var visibleModels: [ModelManager.SDModelConfig] {
        modelManager.sdModels.filter { comparisonMode || $0.id == ModelManager.fluxModelID }
    }
    private var comparisonMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--mim-model-comparison")
        #else
        false
        #endif
    }
    var body: some View {
        let _ = language
        List {
            Section {
                if comparisonMode {
                    Picker("Understanding provider", selection: Binding(get: { modelManager.selectedUnderstandingProvider },
                        set: { modelManager.selectUnderstandingProvider($0) })) {
                        ForEach(UnderstandingProviderID.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(modelManager.assetWritesLocked)
                }
                if CoreAIPhotoUnderstandingService.availability.status != .unsupportedRuntime {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LFM2.5-VL-450M").font(.body.weight(.medium))
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: CoreAIVisionAssets.fragments.reduce(0) { $0 + $1.bytes }, countStyle: .file))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if CoreAIPhotoUnderstandingService.availability.canRun {
                                Label(mt("準備済み"), systemImage: "checkmark.circle")
                            } else {
                                Button(mt("準備")) { modelManager.installUnderstandingModel() }
                                    .disabled(modelManager.assetWritesLocked)
                            }
                        }
                    }.padding(.vertical, 6)
                }
                LabeledContent("Apple Foundation Models", value: mt(modelManager.understandingAvailability.canAnalyze ? "利用可能" : "準備が必要"))
                    .font(.subheadline)
            } header: {
                Text(mt("写真の説明"))
            } footer: {
                Text(mt("LFMを優先して使い、利用できないときはApple Foundation Modelsで処理します。"))
            }
            Section(mt("写真の再現")) {
                if comparisonMode {
                    Picker("Generation runtime", selection: Binding(get: { modelManager.selectedGenerationProvider },
                        set: { modelManager.selectGenerationProvider($0) })) {
                        ForEach(GenerationProviderID.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(modelManager.assetWritesLocked)
                }
                if !modelManager.generationProviderAvailability.canRun {
                    Label(mt(modelManager.generationProviderAvailability.message), systemImage: "exclamationmark.circle")
                }
                if comparisonMode {
                    Picker(mt("再現モデル"), selection: Binding(get: { modelManager.selectedSDModelID },
                                                        set: { modelManager.selectSDModel(id: $0) })) {
                        ForEach(visibleModels) { Text($0.title).tag($0.id) }
                    }
                }
                ForEach(visibleModels) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mt(model.title)).font(.body.weight(.medium))
                        HStack {
                            Text(mt(model.sizeLabel)).foregroundStyle(.secondary)
                            Spacer()
                            if modelManager.isSDModelInstalled(model.id) {
                                Label(mt("準備済み"), systemImage: "checkmark.circle")
                            } else if model.downloadURL != nil {
                                Button(mt("準備")) { modelManager.installSD(modelID: model.id) }
                                    .disabled(modelManager.assetWritesLocked || (model.family == .flux2Klein4B && !CoreAIFluxAssets.runtimeSupported))
                            } else {
                                Button(mt("取り込み")) { importing = true }.disabled(modelManager.assetWritesLocked)
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
            if modelManager.sdInstalling || modelManager.statusMessage != nil {
                Section {
                    if modelManager.sdInstalling {
                        if modelManager.sdTotalBytes > 0 {
                            ProgressView(value: modelManager.sdProgress)
                            Text(ByteCountFormatter.string(fromByteCount: modelManager.sdDownloadedBytes, countStyle: .file) + " / " +
                                 ByteCountFormatter.string(fromByteCount: modelManager.sdTotalBytes, countStyle: .file)).font(.caption)
                            Button(mt("中止")) { modelManager.cancelInstall() }
                        } else { ProgressView(mt("モデルを準備中")) }
                    }
                    if let message = modelManager.statusMessage { Text(mt(message)).font(.callout).foregroundStyle(.secondary) }
                }
            }
        }.scrollContentBackground(.hidden).background(MimStyle.paper)
            .navigationTitle(mt("モデル管理")).navigationBarTitleDisplayMode(.inline)
            .task { modelManager.reloadState() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                Task {
                    do { try await modelManager.importSDXL(from: result.get()) }
                    catch { modelManager.statusMessage = error.localizedDescription }
                }
            }
    }
}
