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
            Text(t(ja: "AIモデルのインストール", en: "Install AI Models", zh: "安装 AI 模型"))
                .font(.largeTitle.bold())
                .padding(.top, 40)

            // MARK: - Description
            Text(t(
                ja: """
このアプリは追加モデルがなくても、そのまま画像投稿と閲覧を始められます。

今はスキップして、あとから設定の「AI モデルの管理」からインストールすることもできます。
画像理解を入れるなら、より文脈に強い Qwen3.5-VL を推奨します。
""",
                en: """
You can start posting and viewing images right away, even without downloading extra models.

You can skip this for now and install models later from Settings under Manage AI Models.
If you want a stronger image-understanding model, Qwen3.5-VL is the recommended option.
""",
                zh: """
即使不下载额外模型，现在也可以直接开始发图和看图。

你可以先跳过，之后再从设置里的“管理 AI 模型”安装。
如果要安装图像理解模型，推荐优先选择更擅长上下文理解的 Qwen3.5-VL。
"""
            ))
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    t(ja: "今はスキップ可", en: "Skipping is OK", zh: "现在可以跳过"),
                    systemImage: "checkmark.circle"
                )
                Label(
                    t(ja: "あとから設定で追加可能", en: "Install later from Settings", zh: "之后可在设置中安装"),
                    systemImage: "gearshape"
                )
                Label(
                    t(ja: "画像理解は Qwen3.5-VL 推奨", en: "Qwen3.5-VL is recommended for image understanding", zh: "图像理解推荐 Qwen3.5-VL"),
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
                Text(t(
                    ja: """
※ モデルのインストール完了後は、
アプリを一度終了して再起動してください。
""",
                    en: """
After installation completes, please close and restart the app.
""",
                    zh: """
安装完成后，请关闭并重新启动应用。
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
               !modelManager.qwenInstalling &&
               !modelManager.sdInstalling &&
               !modelManager.siglipInstalled &&
               !modelManager.qwenInstalled &&
               !modelManager.hasAnySDInstalled {

                Button {
                    dismiss()
                } label: {
                    Text(t(ja: "今はスキップ", en: "Skip for now", zh: "暂时跳过"))
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
                    t(
                        ja: "インストールが完了しました。安定動作のためアプリを再起動してください。",
                        en: "Installation completed. Please restart the app for stable behavior.",
                        zh: "安装完成。为了稳定运行，请重新启动应用。"
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

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
