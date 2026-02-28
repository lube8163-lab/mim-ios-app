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
            Text(t(ja: "AIモデルのインストール", en: "Install AI Models"))
                .font(.largeTitle.bold())
                .padding(.top, 40)

            // MARK: - Description
            Text(t(
                ja: """
画像生成（Stable Diffusion）や画像解析（SigLIP2）を利用するには、
AIモデルのダウンロードが必要です。

必要なモデルは後から個別にインストールできます。
""",
                en: """
To use image generation (Stable Diffusion) and image understanding (SigLIP2),
you need to download the AI models.

You can install each model later as needed.
"""
            ))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // MARK: - Install Content（分離UI）
            ModelInstallContentView(
                modelManager: modelManager
            )
            .frame(maxHeight: 460)
            
            if modelManager.siglipInstalled || modelManager.hasAnySDInstalled {
                Text(t(
                    ja: """
※ モデルのインストール完了後は、
アプリを一度終了して再起動してください。
""",
                    en: """
After installation completes, please close and restart the app.
"""
                ))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // MARK: - Skip Button
            if !modelManager.siglipInstalling &&
               !modelManager.sdInstalling &&
               !modelManager.siglipInstalled &&
               !modelManager.hasAnySDInstalled {

                Button {
                    dismiss()
                } label: {
                    Text(t(ja: "今はスキップ", en: "Skip for now"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
        .padding()
        // インストール中は閉じさせない
        .interactiveDismissDisabled(
            modelManager.siglipInstalling || modelManager.sdInstalling
        )
        .safeAreaInset(edge: .bottom) {
            if showInstallCompletedToast {
                Text(
                    t(
                        ja: "インストールが完了しました。安定動作のためアプリを再起動してください。",
                        en: "Installation completed. Please restart the app for stable behavior."
                    )
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
            wasInstalling = modelManager.siglipInstalling || modelManager.sdInstalling
        }
        .onChange(of: modelManager.siglipInstalling || modelManager.sdInstalling) { installing in
            if wasInstalling && !installing &&
               (modelManager.siglipInstalled || modelManager.hasAnySDInstalled) {
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

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
