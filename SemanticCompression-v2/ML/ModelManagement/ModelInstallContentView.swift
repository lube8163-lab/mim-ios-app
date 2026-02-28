import SwiftUI

struct ModelInstallContentView: View {

    @ObservedObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var deleteTarget: DeleteTarget?

    private enum DeleteTarget: Identifiable {
        case siglip
        case sd(id: String, title: String)

        var id: String {
            switch self {
            case .siglip:
                return "siglip"
            case .sd(let id, _):
                return "sd-\(id)"
            }
        }

        var title: String {
            switch self {
            case .siglip:
                return "SigLIP2 Vision Encoder"
            case .sd(_, let title):
                return title
            }
        }
    }

    var body: some View {
        List {

            Section(header: Text("Image Understanding")) {
                modelRow(
                    title: "SigLIP2 Vision Encoder",
                    size: "170 MB",
                    installed: modelManager.siglipInstalled,
                    installing: modelManager.siglipInstalling,
                    progress: modelManager.siglipProgress,
                    progressDetailText: siglipProgressText,
                    installAction: { modelManager.installSigLIP() },
                    useAction: nil,
                    deleteAction: modelManager.siglipInstalled ? {
                        deleteTarget = .siglip
                    } : nil,
                    isSelected: false
                )
            }

            Section(header: Text("Image Generation")) {
                ForEach(modelManager.sdModels) { model in
                    modelRow(
                        title: model.title,
                        size: model.sizeLabel,
                        installed: modelManager.isSDModelInstalled(model.id),
                        installing: modelManager.isSDModelInstalling(model.id),
                        progress: modelManager.sdProgress,
                        progressDetailText: sdProgressText(for: model.id),
                        installAction: { modelManager.installSD(modelID: model.id) },
                        useAction: (modelManager.isSDModelInstalled(model.id) &&
                                    modelManager.selectedSDModelID != model.id) ? {
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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
                    case .sd(let id, _):
                        modelManager.deleteSDModel(id)
                    }
                },
                secondaryButton: .cancel(Text(t(ja: "キャンセル", en: "Cancel")))
            )
        }
    }

    private var siglipProgressText: String? {
        guard modelManager.siglipInstalling,
              modelManager.siglipTotalBytes > 0 else {
            return nil
        }

        let currentMB = Double(modelManager.siglipDownloadedBytes) / 1024 / 1024
        let totalMB = Double(modelManager.siglipTotalBytes) / 1024 / 1024
        return String(format: "Downloading… %.0f MB / %.0f MB", currentMB, totalMB)
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
                            Text("Using")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.16))
                                .clipShape(Capsule())
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
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
                            Text("Download")
                        }
                    }

                    if let useAction {
                        Button(action: useAction) {
                            Text("Use")
                        }
                    }

                    if let deleteAction {
                        Button(role: .destructive, action: deleteAction) {
                            Text("Delete")
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension ModelInstallContentView {
    func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
