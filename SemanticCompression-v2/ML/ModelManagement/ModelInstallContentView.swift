import SwiftUI

struct ModelInstallContentView: View {

    @ObservedObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var activeAlert: ActiveAlert?

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

    private enum ActiveAlert: Identifiable {
        case delete(DeleteTarget)
        case restartRequired
        case installError(ModelManager.InstallErrorContext)

        var id: String {
            switch self {
            case .delete(let target):
                return "delete-\(target.id)"
            case .restartRequired:
                return "restart-required"
            case .installError(let context):
                return "install-error-\(context.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introCard

                modelSection(
                    title: t(ja: "画像理解", en: "Image Understanding", zh: "图像理解"),
                    subtitle: t(
                        ja: "投稿時の caption / prompt / tags 生成に使います。",
                        en: "Used to generate caption, prompt, and tags when posting.",
                        zh: "用于发帖时生成 caption / prompt / tags。"
                    )
                ) {
                    ForEach(modelManager.imageUnderstandingModels) { model in
                        modelRow(
                            modelID: model.id,
                            title: model.title,
                            size: localizedSizeLabel(ja: model.sizeLabelJA, en: model.sizeLabelEN, zh: model.sizeLabelEN),
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
                                (modelManager.selectedImageUnderstandingModelID != model.id ||
                                 modelManager.selectedImageUnderstandingBackendID != model.id)) ? {
                                    activeAlert = .restartRequired
                                    modelManager.selectImageUnderstandingModel(id: model.id)
                                    modelManager.selectImageUnderstandingBackend(id: model.id)
                                } : nil,
                            deleteAction: modelManager.isImageUnderstandingModelInstalled(model.id) ? {
                                activeAlert = .delete(
                                    model.id == ModelManager.siglipModelID ? .siglip : .qwen
                                )
                            } : nil,
                            isSelected: modelManager.selectedImageUnderstandingModelID == model.id
                        )
                    }
                }

                modelSection(
                    title: t(ja: "画像生成", en: "Image Generation", zh: "图像生成"),
                    subtitle: t(
                        ja: "タイムライン表示用の再構成画像を生成します。",
                        en: "Used to render reconstructed images in the timeline.",
                        zh: "用于生成时间线中的重建图像。"
                    )
                ) {
                    ForEach(modelManager.sdModels) { model in
                        modelRow(
                            modelID: model.id,
                            title: model.title,
                            size: localizedSizeLabel(ja: model.sizeLabelJA, en: model.sizeLabelEN, zh: model.sizeLabelEN),
                            installed: modelManager.isSDModelInstalled(model.id),
                            installing: modelManager.isSDModelInstalling(model.id),
                            progress: modelManager.sdProgress,
                            progressDetailText: sdProgressText(for: model.id),
                            installAction: { modelManager.installSD(modelID: model.id) },
                            useAction: (modelManager.isSDModelInstalled(model.id) &&
                                (modelManager.selectedSDModelID != model.id ||
                                 modelManager.selectedImageGenerationBackend != .stableDiffusion)) ? {
                                    activeAlert = .restartRequired
                                    modelManager.selectSDModel(id: model.id)
                                    modelManager.selectImageGenerationBackend(id: ImageGenerationBackend.stableDiffusion.rawValue)
                                } : nil,
                            deleteAction: modelManager.isSDModelInstalled(model.id) ? {
                                activeAlert = .delete(.sd(id: model.id, title: model.title))
                            } : nil,
                            isSelected: modelManager.selectedSDModelID == model.id
                        )
                    }

                    Text(
                        t(
                            ja: "画像生成モデルのインストール直後や切替直後は、モデル読み込みのため一時的にアプリ操作が重くなったり固まったように見えることがあります。完了まで少し待つか、必要に応じてアプリを再起動してください。",
                            en: "Right after installing or switching an image-generation model, the app may briefly feel unresponsive while the model is loading. Wait a moment for preparation to finish, or restart the app if needed.",
                            zh: "刚安装或切换图像生成模型后，应用在加载模型时可能会暂时变卡或看起来像是无响应。请稍等片刻，必要时可重新启动应用。"
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(
            Color(.systemBackground)
        )
        .onChange(of: modelManager.installError?.id) { _ in
            if let context = modelManager.installError {
                activeAlert = .installError(context)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .delete(let target):
                Alert(
                    title: Text(t(ja: "モデルを削除しますか？", en: "Delete model?", zh: "要删除这个模型吗？")),
                    message: Text(
                        t(
                            ja: "\(target.title) をこの端末から削除します。",
                            en: "This will remove \(target.title) from this device.",
                            zh: "这会从当前设备中移除 \(target.title)。"
                        )
                    ),
                    primaryButton: .destructive(Text(t(ja: "削除", en: "Delete", zh: "删除"))) {
                        switch target {
                        case .siglip:
                            modelManager.deleteSigLIPModel()
                        case .qwen:
                            modelManager.deleteQwenVLModel()
                        case .sd(let id, _):
                            modelManager.deleteSDModel(id)
                        }
                    },
                    secondaryButton: .cancel(Text(t(ja: "キャンセル", en: "Cancel", zh: "取消")))
                )
            case .restartRequired:
                Alert(
                    title: Text(t(ja: "モデル切替を反映しました", en: "Model switch applied", zh: "模型切换已应用")),
                    message: Text(
                        t(
                            ja: "切替を確実に反映するため、アプリを再起動してください。",
                            en: "Please restart the app to ensure the new model is fully applied.",
                            zh: "请重新启动应用，以确保新模型完全生效。"
                        )
                    ),
                    dismissButton: .default(Text("OK"))
                )
            case .installError(let context):
                Alert(
                    title: Text(t(ja: "インストールに失敗しました", en: "Installation failed", zh: "安装失败")),
                    message: Text(installErrorMessage(for: context)),
                    dismissButton: .default(Text("OK")) {
                        modelManager.clearInstallError()
                    }
                )
            }
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
            return progressString(currentMB: currentMB, totalMB: totalMB)
        case ModelManager.qwenVLModelID:
            guard modelManager.qwenInstalling,
                  modelManager.qwenTotalBytes > 0 else {
                return nil
            }
            let currentMB = Double(modelManager.qwenDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.qwenTotalBytes) / 1024 / 1024
            return progressString(currentMB: currentMB, totalMB: totalMB)
        default:
            return nil
        }
    }

    private func sdProgressText(for modelID: String) -> String? {
        guard modelManager.isSDModelInstalling(modelID),
              modelManager.sdTotalBytes > 0 else {
            return t(ja: "インストール中…", en: "Installing…", zh: "安装中…")
        }

        if modelManager.sdDownloadedBytes < modelManager.sdTotalBytes {
            let currentMB = Double(modelManager.sdDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.sdTotalBytes) / 1024 / 1024
            return progressString(currentMB: currentMB, totalMB: totalMB)
        } else {
            return t(ja: "インストール中…", en: "Installing…", zh: "安装中…")
        }
    }

    private func installErrorMessage(for context: ModelManager.InstallErrorContext) -> String {
        switch context.reason {
        case .integrityCheckFailed:
            return t(
                ja: "\(context.modelTitle) のダウンロード後検証に失敗しました。ファイルが壊れているか、配布内容が想定と一致していません。時間をおいて再ダウンロードしてください。",
                en: "Verification failed after downloading \(context.modelTitle). The file may be corrupted or different from the expected package. Please try downloading it again later.",
                zh: "下载 \(context.modelTitle) 后的校验失败。文件可能已损坏，或分发内容与预期不一致。请稍后重试下载。"
            )
        case .generic(let message):
            return t(
                ja: "\(context.modelTitle) のインストールに失敗しました。\n\(message)",
                en: "Failed to install \(context.modelTitle).\n\(message)",
                zh: "安装 \(context.modelTitle) 失败。\n\(message)"
            )
        }
    }

    private func localizedSizeLabel(ja: String, en: String, zh: String? = nil) -> String {
        t(ja: ja, en: en, zh: zh)
    }

    private func progressString(currentMB: Double, totalMB: Double) -> String {
        switch AppLanguage(rawValue: selectedLanguage) ?? .english {
        case .japanese:
            return String(format: "ダウンロード中… %.0f MB / %.0f MB", currentMB, totalMB)
        case .english:
            return String(format: "Downloading… %.0f MB / %.0f MB", currentMB, totalMB)
        case .chineseSimplified:
            return String(format: "下载中… %.0f MB / %.0f MB", currentMB, totalMB)
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
                                text: t(ja: "使用中", en: "Using", zh: "使用中"),
                                tint: Color.accentColor
                            )
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else if installing {
                    statusPill(
                        text: t(ja: "取得中", en: "Downloading", zh: "下载中"),
                        tint: Color.orange
                    )
                }
            }

            if modelID == ModelManager.qwenVLModelID {
                Text(
                    t(
                        ja: "Qwen は画像から caption / prompt / tags を直接生成します。SigLIP より重いですが、より文脈的な出力を狙えます。",
                        en: "Qwen generates caption, prompt, and tags directly from the image. It is heavier than SigLIP but can produce more contextual outputs.",
                        zh: "Qwen 会直接从图像生成 caption / prompt / tags。它比 SigLIP 更重，但能提供更具上下文的信息。"
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.siglipModelID {
                Text(
                    t(
                        ja: "SigLIP2 は画像から特徴量とタグを抽出する軽量モデルです。caption / prompt の組み立てに使われ、プロモードの意味保持率評価にも必要です。",
                        en: "SigLIP2 is a lightweight vision model that extracts embeddings and tags from images. It is used for caption/prompt assembly and is also required for Pro Mode semantic fidelity scoring.",
                        zh: "SigLIP2 是一个轻量级视觉模型，可从图像中提取特征和标签。它用于组装 caption / prompt，也用于 Pro Mode 的语义保真度评分。"
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.sd15ModelID {
                Text(
                    t(
                        ja: "通常版 SD1.5 は品質重視の再構成向けです。元画像ベースの img2img を使えるため、モード差の比較にも向いています。",
                        en: "The standard SD 1.5 model prioritizes reconstruction quality. It supports the starting-image img2img workflow, which makes it better for comparing privacy modes.",
                        zh: "标准版 SD 1.5 更偏向重建质量。它支持基于原图的 img2img 流程，更适合比较不同隐私模式。"
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.sd15LCMModelID {
                Text(
                    t(
                        ja: "LCM は高速生成向けです。img2img（元画像ベース）は無効化されます。",
                        en: "LCM is tuned for speed. img2img (starting-image workflow) is disabled.",
                        zh: "LCM 针对速度进行了优化。img2img（基于原图的流程）将被禁用。"
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
                    Text(t(ja: "インストール中…", en: "Installing…", zh: "安装中…") + " \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    if !installed {
                        Button(action: installAction) {
                            Text(t(ja: "ダウンロード", en: "Download", zh: "下载"))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let useAction {
                        Button(action: useAction) {
                            Text(t(ja: "このモデルを使う", en: "Use this model", zh: "使用这个模型"))
                        }
                        .buttonStyle(.bordered)
                    }

                    if let deleteAction {
                        Button(role: .destructive, action: deleteAction) {
                            Text(t(ja: "削除", en: "Delete", zh: "删除"))
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
            Text(t(ja: "AI Models", en: "AI Models", zh: "AI 模型"))
                .font(.title2.weight(.bold))
            Text(
                t(
                    ja: "ここでは追加モデルのダウンロードや削除、ローカルモデル同士の切替を行えます。Automatic / Apple Vision / Image Playground などの使い分けは設定画面の「AI バックエンド」で選びます。",
                    en: "Use this screen to download, remove, or switch local models. Automatic, Apple Vision, and Image Playground behavior is chosen separately in Settings under AI Backends.",
                    zh: "此页面用于下载、删除或切换本地模型。Automatic、Apple Vision、Image Playground 等行为需在设置里的 AI Backends 中选择。"
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

    func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
