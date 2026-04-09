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
                    title: l("model_management.image_understanding.title"),
                    subtitle: l("model_management.image_understanding.subtitle")
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
                    title: l("model_management.image_generation.title"),
                    subtitle: l("model_management.image_generation.subtitle")
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
                        l("model_management.image_generation.notice")
                    )
                    .font(.caption)
                    .foregroundColor(.orange)

                    Text(
                        l("model_management.image_generation.playground_note")
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
                    title: Text(l("model_management.alert.delete_title")),
                    message: Text(
                        l("model_management.alert.delete_message", target.title)
                    ),
                    primaryButton: .destructive(Text(l("common.delete"))) {
                        switch target {
                        case .siglip:
                            modelManager.deleteSigLIPModel()
                        case .qwen:
                            modelManager.deleteQwenVLModel()
                        case .sd(let id, _):
                            modelManager.deleteSDModel(id)
                        }
                    },
                    secondaryButton: .cancel(Text(l("common.cancel")))
                )
            case .restartRequired:
                Alert(
                    title: Text(l("model_management.alert.switch_applied_title")),
                    message: Text(
                        l("model_management.alert.switch_applied_message")
                    ),
                    dismissButton: .default(Text("OK"))
                )
            case .installError(let context):
                Alert(
                    title: Text(l("model_management.alert.install_failed_title")),
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
            return l("model_management.installing")
        }

        if modelManager.sdDownloadedBytes < modelManager.sdTotalBytes {
            let currentMB = Double(modelManager.sdDownloadedBytes) / 1024 / 1024
            let totalMB = Double(modelManager.sdTotalBytes) / 1024 / 1024
            return progressString(currentMB: currentMB, totalMB: totalMB)
        } else {
            return l("model_management.installing")
        }
    }

    private func installErrorMessage(for context: ModelManager.InstallErrorContext) -> String {
        switch context.reason {
        case .integrityCheckFailed:
            return l("model_management.error.integrity_failed", context.modelTitle)
        case .generic(let message):
            return l("model_management.error.generic", context.modelTitle, message)
        }
    }

    private func localizedSizeLabel(ja: String, en: String, zh: String? = nil) -> String {
        if selectedLanguage.hasPrefix(AppLanguage.japanese.rawValue) {
            return ja
        }
        if selectedLanguage.hasPrefix(AppLanguage.chineseSimplified.rawValue)
            || selectedLanguage.hasPrefix(AppLanguage.chineseTraditional.rawValue) {
            return zh ?? en
        }
        return en
    }

    private func progressString(currentMB: Double, totalMB: Double) -> String {
        l("model_management.progress.download", currentMB, totalMB)
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
                                text: l("model_management.status.using"),
                                tint: Color.accentColor
                            )
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } else if installing {
                    statusPill(
                        text: l("model_management.status.downloading"),
                        tint: Color.orange
                    )
                }
            }

            if modelID == ModelManager.qwenVLModelID {
                Text(
                    l("model_management.model.qwen.description")
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.siglipModelID {
                Text(
                    l("model_management.model.siglip.description")
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.sd15ModelID {
                Text(
                    l("model_management.model.sd15.description")
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if modelID == ModelManager.sd15LCMModelID {
                Text(
                    l("model_management.model.lcm.description")
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
                    Text(l("model_management.installing") + " \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    if !installed {
                        Button(action: installAction) {
                            Text(l("common.download"))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let useAction {
                        Button(action: useAction) {
                            Text(l("model_management.use_model"))
                        }
                        .buttonStyle(.bordered)
                    }

                    if let deleteAction {
                        Button(role: .destructive, action: deleteAction) {
                            Text(l("common.delete"))
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
            Text(l("model_management.intro.title"))
                .font(.title2.weight(.bold))
            Text(
                l("model_management.intro.body")
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

    func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
