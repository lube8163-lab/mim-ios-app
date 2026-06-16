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
    private var selectedLanguage = AppLanguage.preferred.rawValue
    @State private var showInstallCompletedToast = false
    @State private var wasInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            installHeader

            ModelInstallContentView(
                modelManager: modelManager,
                showsIntro: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        // インストール中は閉じさせない
        .interactiveDismissDisabled(
            modelManager.siglipInstalling || modelManager.qwenInstalling || modelManager.sdInstalling
        )
        .safeAreaInset(edge: .bottom) {
            bottomArea
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

    private var installHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l("model_install.title"))
                .font(.title.weight(.bold))
                .foregroundColor(.primary)

            Text(l("model_install.description"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                compactBullet(l("model_install.bullet.skip_ok"), systemImage: "checkmark.circle")
                compactBullet(l("model_install.bullet.install_later"), systemImage: "gearshape")
                compactBullet(l("model_install.bullet.qwen_recommended"), systemImage: "star")
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private func compactBullet(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .foregroundColor(.secondary)
    }

    private var bottomArea: some View {
        VStack(spacing: 8) {
            if showInstallCompletedToast {
                Text(l("model_install.completed_toast"))
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if modelManager.siglipInstalled || modelManager.qwenInstalled || modelManager.hasAnySDInstalled {
                Text(l("model_install.restart_note"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if canSkip {
                Button {
                    dismiss()
                } label: {
                    Text(l("model_install.skip_now"))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    private var canSkip: Bool {
        !modelManager.siglipInstalling &&
        !modelManager.qwenInstalling &&
        !modelManager.sdInstalling &&
        !modelManager.siglipInstalled &&
        !modelManager.qwenInstalled &&
        !modelManager.hasAnySDInstalled
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
