//
//  SettingsView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.proModeEnabledKey)
    private var isProModeEnabled = false
    @AppStorage(AppPreferences.forceSDTextToImageKey)
    private var forceSDTextToImage = false
    @AppStorage(AppPreferences.proModeCacheLimitMBKey)
    private var proModeCacheLimitMB = ImageCacheManager.defaultProModeCacheLimitMB
    @State private var pendingProModeEnabled = false
    @State private var showProModeWarning = false
    @State private var showSigLIPRequirementInfo = false
    @State private var showCacheMaintenanceConfirm = false
    @State private var showSDRestartRequired = false

    var body: some View {
        List {
            Section(t(ja: "一般", en: "General", zh: "通用")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Text(t(ja: "言語設定", en: "Language", zh: "语言"))
                }

                NavigationLink {
                    PrivacyModeSettingsView()
                } label: {
                    Text(t(ja: "投稿モード", en: "Post Mode", zh: "发布模式"))
                }
            }

            Section(t(ja: "AI バックエンド", en: "AI Backends", zh: "AI 后端")) {
                VStack(spacing: 14) {
                    settingsCard(
                        title: t(ja: "AI モデルの管理", en: "Manage AI Models", zh: "管理 AI 模型"),
                        subtitle: t(
                            ja: "追加モデルのダウンロード、削除、使用モデルの切替を行います。",
                            en: "Download, remove, or switch the local models used by the app.",
                            zh: "下载、删除或切换应用使用的本地模型。"
                        )
                    ) {
                        NavigationLink {
                            ModelManagementView()
                                .environmentObject(modelManager)
                        } label: {
                            HStack {
                                Text(t(ja: "管理画面を開く", en: "Open Model Manager", zh: "打开模型管理"))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                    }

                    settingsCard(
                        title: t(ja: "導入状況", en: "Installed Status", zh: "安装状态"),
                        subtitle: installedModelsSummary
                    ) { EmptyView() }

                    settingsCard(
                        title: t(ja: "画像理解", en: "Image Understanding", zh: "图像理解"),
                        subtitle: nil
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            backendMenu(
                                selectionTitle: imageUnderstandingSelectionTitle,
                                options: imageUnderstandingMenuOptions,
                                select: { modelManager.selectImageUnderstandingBackend(id: $0) }
                            )
                        }

                        infoNote(imageUnderstandingBackendDescription)
                    }

                    settingsCard(
                        title: t(ja: "画像生成", en: "Image Generation", zh: "图像生成"),
                        subtitle: nil
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            backendMenu(
                                selectionTitle: imageGenerationSelectionTitle,
                                options: imageGenerationMenuOptions,
                                select: handleImageGenerationBackendSelection
                            )
                        }

                        infoNote(imageGenerationBackendDescription)
                    }
                }
            }

            if modelManager.canUseImagePlaygroundFallback {
                Section(t(ja: "Image Playground", en: "Image Playground", zh: "Image Playground")) {
                    settingsCard(
                        title: t(ja: "スタイル設定", en: "Style", zh: "风格设置"),
                        subtitle: t(
                            ja: "この設定は Image Playground で画像生成するときだけ反映されます。",
                            en: "This setting only applies when images are generated with Image Playground.",
                            zh: "此设置仅在使用 Image Playground 生成图像时生效。"
                        )
                    ) {
                        Picker(
                            t(ja: "Image Playground スタイル", en: "Image Playground Style", zh: "Image Playground 风格"),
                            selection: imagePlaygroundStyleBinding
                        ) {
                            ForEach(ImagePlaygroundStyleOption.allCases) { style in
                                Text(style.displayName).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        infoNote(imagePlaygroundStyleDescription)
                    }
                }
            }

            if modelManager.hasAnySDInstalled {
                Section(t(ja: "Stable Diffusion", en: "Stable Diffusion", zh: "Stable Diffusion")) {
                    settingsCard(
                        title: t(ja: "生成オプション", en: "Generation Options", zh: "生成选项"),
                        subtitle: t(
                            ja: "通常版 SD15 の挙動を必要に応じて調整できます。",
                            en: "Adjust how the standard SD15 pipeline behaves when needed.",
                            zh: "可按需调整标准版 SD15 的生成行为。"
                        )
                    ) {
                        Toggle(
                            t(
                                ja: "初期画像を使わず text2img を優先",
                                en: "Prefer text2img over init image",
                                zh: "优先使用 text2img 而不是初始图像"
                            ),
                            isOn: $forceSDTextToImage
                        )

                        infoNote(
                            t(
                                ja: "L2〜L4 の投稿でも初期画像を使わず、semantic prompt のみで Stable Diffusion を実行します。構図の手がかりは減りますが、初期画像由来のノイズや崩れを避けたいときに有効です。",
                                en: "Even for L2-L4 posts, Stable Diffusion will run without an init image and rely only on the semantic prompt. This reduces structural guidance, but can avoid blur or distortions introduced by the init image.",
                                zh: "即使是 L2-L4 帖子，Stable Diffusion 也不会使用初始图像，而只依赖 semantic prompt。这样会减少构图引导，但有助于避免初始图像带来的噪声与变形。"
                            )
                        )
                    }
                }
            }

            if modelManager.canGenerateImages {
                Section(t(ja: "画像生成", en: "Image Generation", zh: "图像生成")) {
                    Button {
                        NotificationCenter.default.post(name: .regenerateImagesRequested, object: nil)
                    } label: {
                        HStack {
                            Text(t(ja: "表示中の画像を再生成", en: "Regenerate Visible Images", zh: "重新生成当前图片"))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Text(
                        t(
                            ja: "現在表示している投稿画像のキャッシュを削除し、選択中の画像生成モデルで再生成します。",
                            en: "Clear cached images for currently visible posts and regenerate them with the selected image-generation model.",
                            zh: "清除当前可见帖子图片的缓存，并使用当前选中的图像生成模型重新生成。"
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section(t(ja: "プロ機能", en: "Pro Features", zh: "专业功能")) {
                Toggle(isOn: proModeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(ja: "プロモード", en: "Pro Mode", zh: "专业模式"))
                        Text(
                            t(
                                ja: "自分の投稿画像の元画像キャッシュを保持し、再生成結果との意味類似度に加えて、処理時間とメモリ使用量も表示します。メモリ値は処理完了時点のフットプリントです。",
                                en: "Keep original-image cache for your posts and show semantic similarity, processing time, and memory usage for regenerated results. Memory is shown as the footprint at completion.",
                                zh: "为你自己的帖子保留原图缓存，并显示与重建结果的语义相似度、处理时间和内存使用量。内存值显示的是每一步完成时的占用。"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                if isProModeEnabled {
                    Button(role: .destructive) {
                        showCacheMaintenanceConfirm = true
                    } label: {
                        HStack {
                            Text(t(ja: "画像キャッシュを削除", en: "Clear Image Cache", zh: "清除图片缓存"))
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }

                    Text(
                        t(
                            ja: "この操作で再生成キャッシュを削除します。プロモードで保持した元画像キャッシュと意味スコアも削除されます。",
                            en: "This clears regenerated image cache. It also removes retained originals and semantic scores created by Pro Mode.",
                            zh: "此操作会清除重建图片缓存，也会删除专业模式保留的原图缓存和语义评分。"
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if !modelManager.siglipInstalled {
                        Text(
                            t(
                                ja: "意味保持率の計算には SigLIP2 モデルが必要です。未導入でもプロモードは有効化できますが、スコアは表示されません。",
                                en: "SigLIP2 is required for semantic fidelity scoring. You can enable Pro Mode without it, but scores will stay unavailable.",
                                zh: "计算语义保持率需要 SigLIP2 模型。即使未安装也可以开启专业模式，但不会显示评分。"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }

                        Text(
                            t(
                                ja: "メモリ使用量はピーク値ではなく、各処理が終わった時点のフットプリントです。",
                                en: "Memory usage is not a peak reading. It is the footprint measured when each step finishes.",
                                zh: "内存使用量不是峰值，而是每个处理步骤完成时的占用。"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(value: $proModeCacheLimitMB, in: 50...1000, step: 50) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                t(
                                    ja: "プロモードのキャッシュ上限: \(proModeCacheLimitMB) MB",
                                    en: "Pro Mode cache limit: \(proModeCacheLimitMB) MB",
                                    zh: "专业模式缓存上限：\(proModeCacheLimitMB) MB"
                                )
                            )
                            Text(
                                t(
                                    ja: "使用中: \(proModeCacheUsageSummary)",
                                    en: "In use: \(proModeCacheUsageSummary)",
                                    zh: "已使用：\(proModeCacheUsageSummary)"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(t(ja: "このアプリについて", en: "About", zh: "关于本应用")) {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(t(ja: "アプリの説明", en: "App Info", zh: "应用说明"))
                }
            }

            Section(t(ja: "法務", en: "Legal", zh: "法律")) {
                NavigationLink {
                    LegalDocumentsView()
                } label: {
                    Text(t(ja: "プライバシーポリシー / 利用規約", en: "Privacy Policy / Terms", zh: "隐私政策 / 使用条款"))
                }
            }

            Section(t(ja: "ライセンス", en: "Licenses", zh: "许可证")) {
                NavigationLink {
                    LicenseView()
                } label: {
                    Text(t(ja: "使用モデルとライセンス", en: "Models and Licenses", zh: "模型与许可证"))
                }
            }
        }
        .navigationTitle(t(ja: "設定", en: "Settings", zh: "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .alert(
            t(
                ja: "プロモードを有効にしますか？",
                en: "Enable Pro Mode?",
                zh: "要启用专业模式吗？"
            ),
            isPresented: $showProModeWarning
        ) {
            Button(t(ja: "有効化", en: "Enable", zh: "启用"), role: .destructive) {
                isProModeEnabled = pendingProModeEnabled
                if !modelManager.siglipInstalled {
                    showSigLIPRequirementInfo = true
                }
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {
                pendingProModeEnabled = false
            }
        } message: {
            Text(
                t(
                    ja: "プロモードでは、自分が投稿した元画像のキャッシュがアプリ内にこれまで以上に残ります。意味類似度の評価に加え、処理時間とメモリ使用量の表示にも使われます。メモリ値は処理完了時点のフットプリントです。",
                    en: "In Pro Mode, cached originals for images you post will remain in the app for longer and will be used for semantic similarity scoring and performance readouts. Memory is shown as the footprint at completion.",
                    zh: "在专业模式下，你发布图片的原图缓存会在应用内保留更久，并用于语义相似度评分与性能信息显示。内存值显示的是处理完成时的占用。"
                )
            )
        }
        .alert(
            t(
                ja: "画像キャッシュを削除しますか？",
                en: "Clear image cache?",
                zh: "要清除图片缓存吗？"
            ),
            isPresented: $showCacheMaintenanceConfirm
        ) {
            Button(t(ja: "削除する", en: "Clear", zh: "清除"), role: .destructive) {
                NotificationCenter.default.post(name: .semanticCacheMaintenanceRequested, object: nil)
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "再生成画像キャッシュを削除し、プロモードで保持していた元画像キャッシュと意味スコアも消去します。表示中の投稿画像は必要に応じて再生成されます。",
                    en: "This deletes regenerated image cache and also removes retained originals and semantic scores from Pro Mode. Visible post images will regenerate again if needed.",
                    zh: "这会删除重建图片缓存，也会清除专业模式保留的原图缓存和语义评分。当前可见的帖子图片会在需要时重新生成。"
                )
            )
        }
        .alert(
            t(
                ja: "SigLIP2 モデルが必要です",
                en: "SigLIP2 is required",
                zh: "需要 SigLIP2 模型"
            ),
            isPresented: $showSigLIPRequirementInfo
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "プロモードは有効化されましたが、意味保持率の計算には SigLIP2 のインストールが必要です。",
                    en: "Pro Mode is enabled, but SigLIP2 must be installed before semantic fidelity scores can be computed.",
                    zh: "专业模式已启用，但要计算语义保持率仍需先安装 SigLIP2。"
                )
            )
        }
        .alert(
            t(
                ja: "モデル切替を反映しました",
                en: "Model switch applied",
                zh: "模型切换已应用"
            ),
            isPresented: $showSDRestartRequired
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "Stable Diffusion を確実に反映するため、アプリを再起動してください。",
                    en: "Please restart the app to fully apply Stable Diffusion.",
                    zh: "请重新启动应用，以确保 Stable Diffusion 完全生效。"
                )
            )
        }
        .onChange(of: proModeCacheLimitMB) { _ in
            ImageCacheManager.shared.enforceCachePolicies()
        }
    }

    private var proModeBinding: Binding<Bool> {
        Binding(
            get: { isProModeEnabled },
            set: { newValue in
                if newValue {
                    pendingProModeEnabled = true
                    showProModeWarning = true
                } else {
                    pendingProModeEnabled = false
                    isProModeEnabled = false
                }
            }
        )
    }

    private var imagePlaygroundStyleBinding: Binding<String> {
        Binding(
            get: { modelManager.selectedImagePlaygroundStyleID },
            set: { modelManager.selectImagePlaygroundStyle(id: $0) }
        )
    }

    private var proModeCacheUsageSummary: String {
        let bytes = ImageCacheManager.shared.totalCacheUsageBytes(in: [.originalImages, .semanticScores])
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var installedModelsSummary: String {
        let understandingInstalled = modelManager.imageUnderstandingModels.filter {
            modelManager.isImageUnderstandingModelInstalled($0.id)
        }
        let generationInstalled = modelManager.sdModels.filter {
            modelManager.isSDModelInstalled($0.id)
        }

        let understandingText = understandingInstalled.isEmpty
            ? t(ja: "未導入", en: "None installed", zh: "未安装")
            : understandingInstalled.map(\.title).joined(separator: ", ")
        let generationText = generationInstalled.isEmpty
            ? t(ja: "未導入", en: "None installed", zh: "未安装")
            : generationInstalled.map(\.title).joined(separator: ", ")

        return t(
            ja: "画像理解: \(understandingText)\n画像生成: \(generationText)",
            en: "Image understanding: \(understandingText)\nImage generation: \(generationText)",
            zh: "图像理解：\(understandingText)\n图像生成：\(generationText)"
        )
    }

    private var sanitizedImageUnderstandingBackendID: String {
        switch modelManager.selectedImageUnderstandingBackend {
        case .siglip2 where !modelManager.siglipInstalled:
            return ImageUnderstandingBackend.automatic.rawValue
        case .qwen35vl where !modelManager.qwenInstalled:
            return ImageUnderstandingBackend.automatic.rawValue
        case .vision where !modelManager.canUseAppleVisionFallback:
            return ImageUnderstandingBackend.automatic.rawValue
        default:
            return modelManager.selectedImageUnderstandingBackendID
        }
    }

    private var sanitizedImageGenerationBackendID: String {
        switch modelManager.selectedImageGenerationBackend {
        case .stableDiffusion where !modelManager.hasAnySDInstalled:
            return ImageGenerationBackend.automatic.rawValue
        case .imagePlayground where !modelManager.canUseImagePlaygroundFallback:
            return ImageGenerationBackend.automatic.rawValue
        default:
            return modelManager.selectedImageGenerationBackendID
        }
    }

    private var imageUnderstandingSelectionTitle: String {
        let backend = ImageUnderstandingBackend(rawValue: sanitizedImageUnderstandingBackendID) ?? .automatic
        return backend.displayName
    }

    private var imageGenerationSelectionTitle: String {
        let backend = ImageGenerationBackend(rawValue: sanitizedImageGenerationBackendID) ?? .automatic
        return backend == .stableDiffusion ? modelManager.selectedSDModel.title : backend.displayName
    }

    private var imageUnderstandingMenuOptions: [BackendMenuOption] {
        var options = [BackendMenuOption(id: ImageUnderstandingBackend.automatic.rawValue, title: "Automatic")]

        if modelManager.canUseAppleVisionFallback {
            options.append(BackendMenuOption(id: ImageUnderstandingBackend.vision.rawValue, title: "Apple Vision"))
        }

        if modelManager.siglipInstalled {
            options.append(BackendMenuOption(id: ImageUnderstandingBackend.siglip2.rawValue, title: "SigLIP2 Vision Encoder"))
        }

        if modelManager.qwenInstalled {
            options.append(BackendMenuOption(id: ImageUnderstandingBackend.qwen35vl.rawValue, title: "Qwen3.5-VL-0.8B"))
        }

        return options
    }

    private var imageGenerationMenuOptions: [BackendMenuOption] {
        var options = [BackendMenuOption(id: ImageGenerationBackend.automatic.rawValue, title: "Automatic")]

        if modelManager.canUseImagePlaygroundFallback {
            options.append(BackendMenuOption(id: ImageGenerationBackend.imagePlayground.rawValue, title: "Image Playground"))
        }

        if modelManager.hasAnySDInstalled {
            options.append(BackendMenuOption(id: ImageGenerationBackend.stableDiffusion.rawValue, title: "Stable Diffusion"))
        }

        return options
    }

    private var imageUnderstandingBackendDescription: String {
        switch ImageUnderstandingBackend(rawValue: sanitizedImageUnderstandingBackendID) ?? .automatic {
        case .automatic:
            return t(
                ja: "自動選択です。追加モデルがあればそれを使い、無ければ Apple Vision にフォールバックします。",
                en: "Automatic mode prefers installed models and falls back to Apple Vision when none are available.",
                zh: "自动模式会优先使用已安装模型，没有时回退到 Apple Vision。"
            )
        case .vision:
            return t(
                ja: "Apple Vision で軽量なタグ分類を行い、簡易 prompt を作ります。追加ダウンロード不要で使えます。",
                en: "Apple Vision performs lightweight tag classification and builds a simple prompt without extra downloads.",
                zh: "Apple Vision 会进行轻量标签分类，并生成简易 prompt，无需额外下载。"
            )
        case .siglip2:
            return t(
                ja: "SigLIP2 は軽量で安定したタグ抽出に向いており、プロモードの意味保持率評価にも使われます。",
                en: "SigLIP2 is a lighter, stable tag extractor and is also used for Pro Mode semantic fidelity scoring.",
                zh: "SigLIP2 更轻量，适合稳定提取标签，也用于专业模式的语义保持率评分。"
            )
        case .qwen35vl:
            return t(
                ja: "Qwen3.5-VL は caption / prompt / tags を直接生成しやすく、より文脈的な説明になりやすいです。",
                en: "Qwen3.5-VL tends to generate captions, prompts, and tags more directly with richer context.",
                zh: "Qwen3.5-VL 更容易直接生成 caption / prompt / tags，语境通常更丰富。"
            )
        }
    }

    private var imageGenerationBackendDescription: String {
        switch ImageGenerationBackend(rawValue: sanitizedImageGenerationBackendID) ?? .automatic {
        case .automatic:
            return t(
                ja: "自動選択です。Stable Diffusion があればそれを使い、無ければ Image Playground を使います。",
                en: "Automatic mode prefers Stable Diffusion and falls back to Image Playground when it is unavailable.",
                zh: "自动模式会优先使用 Stable Diffusion，不可用时改用 Image Playground。"
            )
        case .imagePlayground:
            return t(
                ja: "Image Playground は Apple の標準生成機能です。モデル未導入でも端末だけで再構成画像を作れます。",
                en: "Image Playground is Apple's built-in generator and can reconstruct images without downloading extra models.",
                zh: "Image Playground 是 Apple 内建生成器，无需下载额外模型也能重建图像。"
            )
        case .stableDiffusion:
            return t(
                ja: "Stable Diffusion はダウンロード済みモデルで再構成します。通常版は img2img を使え、LCM は高速です。",
                en: "Stable Diffusion reconstructs images with downloaded models. The standard model supports img2img, while LCM is faster.",
                zh: "Stable Diffusion 会用已下载模型进行重建。标准版支持 img2img，LCM 更快。"
            )
        }
    }

    private var imagePlaygroundStyleDescription: String {
        switch modelManager.selectedImagePlaygroundStyle {
        case .animation:
            return t(
                ja: "Animation はややポップで柔らかい見た目になりやすいスタイルです。",
                en: "Animation tends to produce softer, more playful-looking results.",
                zh: "Animation 往往会生成更柔和、更活泼的视觉效果。"
            )
        case .illustration:
            return t(
                ja: "Illustration は最も標準的で、バランスの良い見た目になりやすいスタイルです。",
                en: "Illustration is the most balanced and default-looking style.",
                zh: "Illustration 是最均衡、最标准的一种风格。"
            )
        case .sketch:
            return t(
                ja: "Sketch は線の印象が残りやすく、ラフなドローイング寄りの見た目になります。",
                en: "Sketch preserves more linework and gives results a rougher drawing-like feel.",
                zh: "Sketch 会保留更多线条感，整体更接近草图或手绘。"
            )
        }
    }

    private func handleImageGenerationBackendSelection(_ id: String) {
        guard imageGenerationMenuOptions.contains(where: { $0.id == id }) else { return }

        let previous = sanitizedImageGenerationBackendID
        modelManager.selectImageGenerationBackend(id: id)

        if id == ImageGenerationBackend.stableDiffusion.rawValue && previous != id {
            NotificationCenter.default.post(name: .deferStableDiffusionReloadUntilRestart, object: nil)
            showSDRestartRequired = true
        }
    }

    private func backendMenu(
        selectionTitle: String,
        options: [BackendMenuOption],
        select: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    select(option.id)
                } label: {
                    Text(option.title)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectionTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private struct BackendMenuOption: Identifiable {
        let id: String
        let title: String
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            let builtContent = content()
            builtContent
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func infoNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
