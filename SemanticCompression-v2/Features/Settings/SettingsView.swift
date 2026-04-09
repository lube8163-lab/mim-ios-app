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
            Section(l("settings.section.general")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Text(l("settings.general.language"))
                }

                NavigationLink {
                    PrivacyModeSettingsView()
                } label: {
                    Text(l("settings.general.post_mode"))
                }
            }

            Section(l("settings.section.ai_backends")) {
                VStack(spacing: 14) {
                    settingsCard(
                        title: l("settings.ai.manage_models.title"),
                        subtitle: l("settings.ai.manage_models.subtitle")
                    ) {
                        NavigationLink {
                            ModelManagementView()
                                .environmentObject(modelManager)
                        } label: {
                            HStack {
                                Text(l("settings.ai.manage_models.open"))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                    }

                    settingsCard(
                        title: l("settings.ai.installed_status"),
                        subtitle: installedModelsSummary
                    ) { EmptyView() }

                    settingsCard(
                        title: l("settings.ai.image_understanding"),
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
                        title: l("settings.ai.image_generation"),
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
                Section(l("settings.section.image_playground")) {
                    settingsCard(
                        title: l("settings.image_playground.style.title"),
                        subtitle: l("settings.image_playground.style.subtitle")
                    ) {
                        Picker(
                            l("settings.image_playground.style.picker"),
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
                Section(l("settings.section.stable_diffusion")) {
                    settingsCard(
                        title: l("settings.sd.options.title"),
                        subtitle: l("settings.sd.options.subtitle")
                    ) {
                        Toggle(
                            l("settings.sd.options.prefer_text2img"),
                            isOn: $forceSDTextToImage
                        )

                        infoNote(l("settings.sd.options.note"))
                    }
                }
            }

            if modelManager.canGenerateImages {
                Section(l("settings.section.image_generation")) {
                    Button {
                        NotificationCenter.default.post(name: .regenerateImagesRequested, object: nil)
                    } label: {
                        HStack {
                            Text(l("settings.image_generation.regenerate_visible"))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Text(l("settings.image_generation.regenerate_visible.note"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section(l("settings.section.pro_features")) {
                Toggle(isOn: proModeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l("settings.pro_mode.title"))
                        Text(l("settings.pro_mode.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                if isProModeEnabled {
                    Button(role: .destructive) {
                        showCacheMaintenanceConfirm = true
                    } label: {
                        HStack {
                            Text(l("settings.pro_mode.clear_cache"))
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }

                    Text(l("settings.pro_mode.clear_cache.note"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if !modelManager.siglipInstalled {
                        Text(l("settings.pro_mode.siglip_missing"))
                        .font(.caption)
                        .foregroundColor(.orange)
                    }

                        Text(
                            l("settings.pro_mode.memory_note")
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(value: $proModeCacheLimitMB, in: 50...1000, step: 50) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                l("settings.pro_mode.cache_limit", proModeCacheLimitMB)
                            )
                            Text(
                                l("settings.pro_mode.cache_in_use", proModeCacheUsageSummary)
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(l("settings.section.about")) {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(l("settings.about.app_info"))
                }
            }

            Section(l("settings.section.legal")) {
                NavigationLink {
                    LegalDocumentsView()
                } label: {
                    Text(l("settings.legal.privacy_terms"))
                }
            }

            Section(l("settings.section.licenses")) {
                NavigationLink {
                    LicenseView()
                } label: {
                    Text(l("settings.licenses.models_and_licenses"))
                }
            }
        }
        .navigationTitle(l("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .alert(
            l("settings.alert.enable_pro_mode.title"),
            isPresented: $showProModeWarning
        ) {
            Button(l("settings.alert.enable_pro_mode.enable"), role: .destructive) {
                isProModeEnabled = pendingProModeEnabled
                if !modelManager.siglipInstalled {
                    showSigLIPRequirementInfo = true
                }
            }
            Button(l("common.cancel"), role: .cancel) {
                pendingProModeEnabled = false
            }
        } message: {
            Text(l("settings.alert.enable_pro_mode.message"))
        }
        .alert(
            l("settings.alert.clear_cache.title"),
            isPresented: $showCacheMaintenanceConfirm
        ) {
            Button(l("settings.alert.clear_cache.confirm"), role: .destructive) {
                NotificationCenter.default.post(name: .semanticCacheMaintenanceRequested, object: nil)
            }
            Button(l("common.cancel"), role: .cancel) {}
        } message: {
            Text(l("settings.alert.clear_cache.message"))
        }
        .alert(
            l("settings.alert.siglip_required.title"),
            isPresented: $showSigLIPRequirementInfo
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(l("settings.alert.siglip_required.message"))
        }
        .alert(
            l("settings.alert.model_switch.title"),
            isPresented: $showSDRestartRequired
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(l("settings.alert.model_switch.message"))
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
            ? l("settings.installed.none")
            : understandingInstalled.map(\.title).joined(separator: ", ")
        let generationText = generationInstalled.isEmpty
            ? l("settings.installed.none")
            : generationInstalled.map(\.title).joined(separator: ", ")

        return l("settings.installed.summary", understandingText, generationText)
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
            return l("settings.backend.image_understanding.automatic")
        case .vision:
            return l("settings.backend.image_understanding.vision")
        case .siglip2:
            return l("settings.backend.image_understanding.siglip2")
        case .qwen35vl:
            return l("settings.backend.image_understanding.qwen")
        }
    }

    private var imageGenerationBackendDescription: String {
        switch ImageGenerationBackend(rawValue: sanitizedImageGenerationBackendID) ?? .automatic {
        case .automatic:
            return l("settings.backend.image_generation.automatic")
        case .imagePlayground:
            return l("settings.backend.image_generation.image_playground")
        case .stableDiffusion:
            return l("settings.backend.image_generation.stable_diffusion")
        }
    }

    private var imagePlaygroundStyleDescription: String {
        switch modelManager.selectedImagePlaygroundStyle {
        case .animation:
            return l("settings.image_playground.style.animation")
        case .illustration:
            return l("settings.image_playground.style.illustration")
        case .sketch:
            return l("settings.image_playground.style.sketch")
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

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
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
