import SwiftUI

struct ModelInstallContentView: View {

    @ObservedObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var deleteTarget: DeleteTarget?
    @State private var showRestartRequiredNotice = false

    private enum DeleteTarget: Identifiable {
        case siglip
        case qwen
        case sd(id: String, title: String)

        var id: String {
            switch self {
            case .siglip:
                return "siglip"
            case .qwen:
                return "qwen"
            case .sd(let id, _):
                return "sd-\(id)"
            }
        }

        var title: String {
            switch self {
            case .siglip:
                return "SigLIP2 Vision Encoder"
            case .qwen:
                return "Qwen3.5-VL-0.8B"
            case .sd(_, let title):
                return title
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introCard

                modelSection(
                    title: t(ja: "画像理解", en: "Image Understanding"),
                    subtitle: t(
                        ja: "投稿時の caption / prompt / tags 生成に使います。",
                        en: "Used to generate caption, prompt, and tags when posting."
                    )
                ) {
                    ForEach(modelManager.imageUnderstandingModels) { model in
                        modelRow(
                            modelID: model.id,
                            title: model.title,
                            size: model.sizeLabel,
                            installed: modelManager.isImageUnderstandingModelInstalled(model.id),
                            installing: modelManager.isImageUnderstandingModelInstalling(model.id),
                            progress: understandingProgress(for: model.id),
                            progressDetailText: understandingProgressText(for: model.id),
                            installAction: {
                                if model.id == ModelManager.siglipModelID {
                                    modelManager.installSigLIP()
                                } else {
                                    modelManager.installQwenVL()
                                }
                            },
                            useAction: (modelManager.isImageUnderstandingModelInstalled(model.id) &&
                                modelManager.selectedImageUnderstandingModelID != model.id) ? {
                                    modelManager.selectImageUnderstandingModel(id: model.id)
                                } : nil,
                            deleteAction: modelManager.isImageUnderstandingModelInstalled(model.id) ? {
                                deleteTarget = model.id == ModelManager.siglipModelID ? .siglip : .qwen
                            } : nil,
                            isSelected: modelManager.selectedImageUnderstandingModelID == model.id
                        )
                    }
                }

                modelSection(
                    title: t(ja: "画像生成", en: "Image Generation"),
                    subtitle: t(
                        ja: "タイムライン表示用の再構成画像を生成します。",
                        en: "Used to render reconstructed images in the timeline."
                    )
                ) {
                    ForEach(modelManager.sdModels) { model in
                        modelRow(
                            modelID: model.id,
                            title: model.title,
                            size: model.sizeLabel,
                            installed: modelManager.isSDModelInstalled(model.id),
                            installing: modelManager.isSDModelInstalling(model.id),
                            progress: modelManager.sdProgress,
                            progressDetailText: sdProgressText(for: model.id),
                            installAction: { modelManager.installSD(modelID: model.id) },
                            useAction: (modelManager.isSDModelInstalled(model.id) &&
                                modelManager.selectedSDModelID != model.id) ? {
                                    showRestartRequiredNotice = true
                                    modelManager.selectSDModel(id: model.id)
                                } : nil,
                            deleteAction: modelManager.isSDModelInstalled(model.id) ? {
                                deleteTarget = .sd(id: model.id, title: model.title)
                            } : nil,
                            isSelected: modelManager.selectedSDModelID == model.id
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(
            Color(.systemBackground)
        )
        .alert(item: $deleteTarget) { target in
            Alert(
                title: Text(t(ja: "モデルを削除しますか？", en: "Delete model?")),
                message: Text(
                    t(
                        ja: "\(target.title) をこの端末から削除します。",
                        en: "This will remove \(target.title) from this device."
                    )
                ),
                primaryButton: .destructive(Text(t(ja: "削除", en: "Delete"))) {
                    switch target {
                    case .siglip:
                        modelManager.deleteSigLIPModel()
                    case .qwen:
                        modelManager.deleteQwenVLModel()
                    case .sd(let id, _):
                        modelManager.deleteSDModel(id)
                    }
                },
                secondaryButton: .cancel(Text(t(ja: "キャンセル", en: "Cancel")))
            )
        }
        .alert(
            t(ja: "モデル切替を反映しました", en: "Model switch applied"),
            isPresented: $showRestartRequiredNotice
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "切替を確実に反映するため、アプリを再起動してください。",
                    en: "Please restart the app to ensure the new model is fully applied."
                )
            )
        }
    }

    private func understandingProgress(for modelID: String) -> Double {
        switch modelID {
        case ModelManager.siglipModelID:
            return modelManager.siglipProgress
        case ModelManager.qwenVLModelID:
            return modelManager.qwenProgress
        default:
            return 0
        }
    }

    private func understandingProgressText(for modelID: String) -> String? {
        switch modelID {
        case ModelManager.siglipModelID:
            guard modelManager.siglipInstalling,
                  modelManager.siglipTotalBytes > 0 else {
                return nil
            }
            let currentMB = Double(modelManager.siglipDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.siglipTotalBytes) / 1024 / 1024
            return String(format: "Downloading… %.0f MB / %.0f MB", currentMB, totalMB)
        case ModelManager.qwenVLModelID:
            guard modelManager.qwenInstalling,
                  modelManager.qwenTotalBytes > 0 else {
                return nil
            }
            let currentMB = Double(modelManager.qwenDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.qwenTotalBytes) / 1024 / 1024
            return String(format: "Downloading… %.0f MB / %.0f MB", currentMB, totalMB)
        default:
            return nil
        }
    }

    private func sdProgressText(for modelID: String) -> String? {
        guard modelManager.isSDModelInstalling(modelID),
              modelManager.sdTotalBytes > 0 else {
            return "Installing…"
        }

        if modelManager.sdDownloadedBytes < modelManager.sdTotalBytes {
            let currentMB = Double(modelManager.sdDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.sdTotalBytes) / 1024 / 1024
            return String(format: "Downloading… %.0f MB / %.0f MB", currentMB, totalMB)
        } else {
            return "Installing…"
        }
    }

    @ViewBuilder
    private func modelRow(
        modelID: String?,
        title: String,
        size: String,
        installed: Bool,
        installing: Bool,
        progress: Double,
        progressDetailText: String?,
        installAction: @escaping () -> Void,
        useAction: (() -> Void)?,
        deleteAction: (() -> Void)?,
        isSelected: Bool
    ) -> some View {

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if installed {
                    HStack(spacing: 8) {
                        if isSelected {
                            statusPill(
                                text: t(ja: "使用中", en: "Using"),
                                tint: Color.accentColor
                            )
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else if installing {
                    statusPill(
                        text: t(ja: "取得中", en: "Downloading"),
                        tint: Color.orange
                    )
                }
            }

            if modelID == ModelManager.qwenVLModelID {
                Text(
                    t(
                        ja: "Qwen は画像から caption / prompt / tags を直接生成します。SigLIP より重いですが、より文脈的な出力を狙えます。",
                        en: "Qwen generates caption, prompt, and tags directly from the image. It is heavier than SigLIP but can produce more contextual outputs."
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.sd15LCMModelID {
                Text(
                    t(
                        ja: "LCM は高速生成向けです。img2img（元画像ベース）は無効化されます。",
                        en: "LCM is tuned for speed. img2img (starting-image workflow) is disabled."
                    )
                )
                .font(.caption2)
                .foregroundColor(.orange)
            }

            if installing {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                if let detail = progressDetailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Installing… \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    if !installed {
                        Button(action: installAction) {
                            Text(t(ja: "ダウンロード", en: "Download"))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let useAction {
                        Button(action: useAction) {
                            Text(t(ja: "このモデルを使う", en: "Use this model"))
                        }
                        .buttonStyle(.bordered)
                    }

                    if let deleteAction {
                        Button(role: .destructive, action: deleteAction) {
                            Text(t(ja: "削除", en: "Delete"))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private extension ModelInstallContentView {
    var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t(ja: "AI Models", en: "AI Models"))
                .font(.title2.weight(.bold))
            Text(
                t(
                    ja: "用途ごとにモデルを管理できます。\"使用中\" のモデルが実際の投稿生成やタイムライン再構成に使われます。",
                    en: "Manage models by purpose. Models marked as 'Using' are the ones currently used for posting and timeline reconstruction."
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    func modelSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 14) {
                content()
            }
        }
    }

    func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundColor(tint)
    }

    func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
