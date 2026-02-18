import SwiftUI

struct PrivacyModeSettingsView: View {
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
                    en: "Choose the default privacy mode for posting. The selected mode changes the intermediate payload sent and how the initial image is reconstructed."
                ))
                .font(.footnote)
                .foregroundColor(.secondary)
            }

            Section(t(ja: "既定の投稿モード", en: "Default Post Mode")) {
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
                }
            }
        }
        .navigationTitle(t(ja: "投稿モード", en: "Post Mode"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            t(
                ja: "L4 は再現性が高い一方、プライバシーは弱くなります。続行しますか？",
                en: "L4 improves reconstruction but weakens privacy. Continue?"
            ),
            isPresented: $showL4Warning
        ) {
            Button(t(ja: "続行", en: "Continue"), role: .destructive) {
                previousModeRawBeforeL4Warning = nil
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {
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
            return t(ja: "L1 フルプライバシー", en: "L1 Full Privacy")
        case .l2:
            return t(ja: "L2 セマンティックブラー", en: "L2 Semantic Blur")
        case .l3:
            return t(ja: "L3 ソフト再構成", en: "L3 Soft Reconstruction")
        case .l2Prime:
            return t(ja: "L4 極低解像度", en: "L4 Extreme Low-Res")
        }
    }

    private func description(for mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return t(ja: "画像情報を送信しない。再現性は低いがプライバシー最優先。", en: "No image payload is sent. Lowest reconstruction, highest privacy.")
        case .l2:
            return t(ja: "軽量要約（ThumbHash）を送信。初期導入の推奨モード。", en: "Sends a compact summary (ThumbHash). Recommended default mode.")
        case .l3:
            return t(ja: "低周波DCT係数を送信。再現性と保護のバランスを調整。", en: "Sends low-frequency DCT coefficients for balanced reconstruction/privacy.")
        case .l2Prime:
            return t(ja: "極低解像ピクセルを送信。再現性は高いが保護は弱め。", en: "Sends extreme low-res pixels. Better reconstruction, weaker privacy.")
        }
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
