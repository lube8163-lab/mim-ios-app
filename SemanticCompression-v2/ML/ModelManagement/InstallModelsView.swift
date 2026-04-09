//
//  InstallModelsView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/10.
//


import SwiftUI

struct InstallModelsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var showInstallCompletedToast = false
    @State private var wasInstalling = false

    var body: some View {
        VStack(spacing: 24) {

            // MARK: - Title
            Text(l("model_install.title"))
                .font(.largeTitle.bold())
                .padding(.top, 40)

            // MARK: - Description
            Text(l("model_install.description"))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    l("model_install.bullet.skip_ok"),
                    systemImage: "checkmark.circle"
                )
                Label(
                    l("model_install.bullet.install_later"),
                    systemImage: "gearshape"
                )
                Label(
                    l("model_install.bullet.qwen_recommended"),
                    systemImage: "star"
                )
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 8)

            // MARK: - Install Content（分離UI）
            ModelInstallContentView(
                modelManager: modelManager
            )
            .frame(maxHeight: 460)
            
            if modelManager.siglipInstalled || modelManager.qwenInstalled || modelManager.hasAnySDInstalled {
                Text(l("model_install.restart_note"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // MARK: - Skip Button
            if !modelManager.siglipInstalling &&
               !modelManager.qwenInstalling &&
               !modelManager.sdInstalling &&
               !modelManager.siglipInstalled &&
               !modelManager.qwenInstalled &&
               !modelManager.hasAnySDInstalled {

                Button {
                    dismiss()
                } label: {
                    Text(l("model_install.skip_now"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
        .padding()
        // インストール中は閉じさせない
        .interactiveDismissDisabled(
            modelManager.siglipInstalling || modelManager.qwenInstalling || modelManager.sdInstalling
        )
        .safeAreaInset(edge: .bottom) {
            if showInstallCompletedToast {
                Text(
                    l("model_install.completed_toast")
                )
                .font(.footnote)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.78))
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showInstallCompletedToast)
        .onAppear {
            wasInstalling = modelManager.siglipInstalling || modelManager.qwenInstalling || modelManager.sdInstalling
        }
        .onChange(of: modelManager.siglipInstalling || modelManager.qwenInstalling || modelManager.sdInstalling) { installing in
            if wasInstalling && !installing &&
               (modelManager.siglipInstalled || modelManager.qwenInstalled || modelManager.hasAnySDInstalled) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInstallCompletedToast = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showInstallCompletedToast = false
                    }
                }
            }
            wasInstalling = installing
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
