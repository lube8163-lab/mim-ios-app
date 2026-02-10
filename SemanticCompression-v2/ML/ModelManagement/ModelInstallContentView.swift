import SwiftUI

struct ModelInstallContentView: View {

    @ObservedObject var modelManager: ModelManager

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
                    installAction: {
                        Task {
                            try? await modelManager.installSigLIP()
                        }
                    }
                )
            }

            Section(header: Text("Image Generation")) {
                modelRow(
                    title: "Stable Diffusion 1.5",
                    size: "約4 GB（Wi-Fi 推奨）",
                    installed: modelManager.sdInstalled,
                    installing: modelManager.sdInstalling,
                    progress: modelManager.sdProgress,
                    progressDetailText: sdProgressText,
                    installAction: {
                        Task {
                            try? await modelManager.installSD()
                        }
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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

    private var sdProgressText: String? {
        guard modelManager.sdInstalling,
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
        installAction: @escaping () -> Void
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
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
            } else if !installed {
                Button(action: installAction) {
                    Text("Download")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
