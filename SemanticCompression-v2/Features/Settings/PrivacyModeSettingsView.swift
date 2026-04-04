import SwiftUI

struct PrivacyModeSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.selectedPrivacyModeKey)
    private var selectedModeRaw = PrivacyMode.l2.storageValue
    @State private var showL4Warning = false
    @State private var previousModeRawBeforeL4Warning: Int?

    var body: some View {
        List {
            Section {
                Text(t(
                    ja: "投稿時に使う既定のプライバシーモードを選択します。モードに応じて、送信する中間表現と再構成のされ方が変わります。",
                    en: "Choose the default privacy mode for posting. The selected mode changes the intermediate payload sent and how the initial image is reconstructed.",
                    zh: "选择发帖时默认使用的隐私模式。不同模式会改变发送的中间表示以及初始图像的重建方式。"
                ))
                .font(.footnote)
                .foregroundColor(.secondary)

                if modelManager.resolvedImageGenerationBackend == .stableDiffusion &&
                    modelManager.selectedSDModelID == ModelManager.sd15LCMModelID {
                    Text(
                        t(
                            ja: "LCM 使用中は投稿モード変更が無効です（高速生成優先・img2img 無効）。",
                            en: "Post mode switching is disabled while LCM is selected (speed-first, img2img off).",
                            zh: "选择 LCM 时将无法切换发布模式（优先速度，禁用 img2img）。"
                        )
                    )
                    .font(.footnote)
                    .foregroundColor(.orange)
                }
            }

            Section(t(ja: "既定の投稿モード", en: "Default Post Mode", zh: "默认发布模式")) {
                ForEach(PrivacyMode.allCases) { mode in
                    Button {
                        guard PrivacyModeAccessPolicy.canUse(mode: mode) else { return }
                        let current = PrivacyMode.fromStorageValue(selectedModeRaw)
                        if current != .l2Prime && mode == .l2Prime {
                            previousModeRawBeforeL4Warning = selectedModeRaw
                            selectedModeRaw = mode.storageValue
                            showL4Warning = true
                        } else {
                            previousModeRawBeforeL4Warning = nil
                            selectedModeRaw = mode.storageValue
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.iconName)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(for: mode))
                                Text(description(for: mode))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if mode.storageValue == selectedModeRaw {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(!PrivacyModeAccessPolicy.canUse(mode: mode))
                    .disabled(
                        modelManager.resolvedImageGenerationBackend == .stableDiffusion &&
                        modelManager.selectedSDModelID == ModelManager.sd15LCMModelID
                    )
                }
            }
        }
        .navigationTitle(t(ja: "投稿モード", en: "Post Mode", zh: "发布模式"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            t(
                ja: "L4 は再現性が高い一方、プライバシーは弱くなります。続行しますか？",
                en: "L4 improves reconstruction but weakens privacy. Continue?",
                zh: "L4 会提升重建效果，但隐私保护会减弱。要继续吗？"
            ),
            isPresented: $showL4Warning
        ) {
            Button(t(ja: "続行", en: "Continue", zh: "继续"), role: .destructive) {
                previousModeRawBeforeL4Warning = nil
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {
                if let previousModeRawBeforeL4Warning {
                    selectedModeRaw = previousModeRawBeforeL4Warning
                }
                self.previousModeRawBeforeL4Warning = nil
            }
        }
    }

    private func label(for mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return t(ja: "L1 フルプライバシー", en: "L1 Full Privacy", zh: "L1 完全隐私")
        case .l2:
            return t(ja: "L2 セマンティックブラー", en: "L2 Semantic Blur", zh: "L2 语义模糊")
        case .l3:
            return t(ja: "L3 ソフト再構成", en: "L3 Soft Reconstruction", zh: "L3 柔性重建")
        case .l2Prime:
            return t(ja: "L4 極低解像度", en: "L4 Extreme Low-Res", zh: "L4 极低分辨率")
        }
    }

    private func description(for mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return t(ja: "画像情報を送信しない。再現性は低いがプライバシー最優先。", en: "No image payload is sent. Lowest reconstruction, highest privacy.", zh: "不发送图像信息。重建能力最低，但隐私保护最高。")
        case .l2:
            return t(ja: "軽量要約（ThumbHash）を送信。初期導入の推奨モード。", en: "Sends a compact summary (ThumbHash). Recommended default mode.", zh: "发送轻量摘要（ThumbHash）。推荐作为默认模式。")
        case .l3:
            return t(ja: "低周波DCT係数を送信。再現性と保護のバランスを調整。", en: "Sends low-frequency DCT coefficients for balanced reconstruction/privacy.", zh: "发送低频 DCT 系数，在重建效果与隐私之间取得平衡。")
        case .l2Prime:
            return t(ja: "極低解像ピクセルを送信。再現性は高いが保護は弱め。", en: "Sends extreme low-res pixels. Better reconstruction, weaker privacy.", zh: "发送极低分辨率像素。重建更好，但隐私保护较弱。")
        }
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
