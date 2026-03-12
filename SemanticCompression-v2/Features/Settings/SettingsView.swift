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
    @AppStorage(AppPreferences.proModeCacheLimitMBKey)
    private var proModeCacheLimitMB = ImageCacheManager.defaultProModeCacheLimitMB
    @State private var pendingProModeEnabled = false
    @State private var showProModeWarning = false
    @State private var showSigLIPRequirementInfo = false
    @State private var showCacheMaintenanceConfirm = false

    var body: some View {
        List {
            Section(t(ja: "一般", en: "General")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Text(t(ja: "言語設定", en: "Language"))
                }

                NavigationLink {
                    PrivacyModeSettingsView()
                } label: {
                    Text(t(ja: "投稿モード", en: "Post Mode"))
                }
            }

            Section(t(ja: "プロ機能", en: "Pro Features")) {
                Toggle(isOn: proModeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(ja: "プロモード", en: "Pro Mode"))
                        Text(
                            t(
                                ja: "自分の投稿画像の元画像キャッシュを保持し、再生成結果との意味類似度に加えて、処理時間とメモリ使用量も表示します。メモリ値は処理完了時点のフットプリントです。",
                                en: "Keep original-image cache for your posts and show semantic similarity, processing time, and memory usage for regenerated results. Memory is shown as the footprint at completion."
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                if isProModeEnabled {
                    Button(role: .destructive) {
                        showCacheMaintenanceConfirm = true
                    } label: {
                        HStack {
                            Text(t(ja: "画像キャッシュを削除", en: "Clear Image Cache"))
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }

                    Text(
                        t(
                            ja: "この操作で再生成キャッシュを削除します。プロモードで保持した元画像キャッシュと意味スコアも削除されます。",
                            en: "This clears regenerated image cache. It also removes retained originals and semantic scores created by Pro Mode."
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if !modelManager.siglipInstalled {
                        Text(
                            t(
                                ja: "意味保持率の計算には SigLIP2 モデルが必要です。未導入でもプロモードは有効化できますが、スコアは表示されません。",
                                en: "SigLIP2 is required for semantic fidelity scoring. You can enable Pro Mode without it, but scores will stay unavailable."
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }

                        Text(
                            t(
                                ja: "メモリ使用量はピーク値ではなく、各処理が終わった時点のフットプリントです。",
                                en: "Memory usage is not a peak reading. It is the footprint measured when each step finishes."
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(value: $proModeCacheLimitMB, in: 50...1000, step: 50) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                t(
                                    ja: "プロモードのキャッシュ上限: \(proModeCacheLimitMB) MB",
                                    en: "Pro Mode cache limit: \(proModeCacheLimitMB) MB"
                                )
                            )
                            Text(
                                t(
                                    ja: "使用中: \(proModeCacheUsageSummary)",
                                    en: "In use: \(proModeCacheUsageSummary)"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(t(ja: "このアプリについて", en: "About")) {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(t(ja: "アプリの説明", en: "App Info"))
                }
            }

            Section(t(ja: "法務", en: "Legal")) {
                NavigationLink {
                    LegalDocumentsView()
                } label: {
                    Text(t(ja: "プライバシーポリシー / 利用規約", en: "Privacy Policy / Terms"))
                }
            }

            Section(t(ja: "ライセンス", en: "Licenses")) {
                NavigationLink {
                    LicenseView()
                } label: {
                    Text(t(ja: "使用モデルとライセンス", en: "Models and Licenses"))
                }
            }
        }
        .navigationTitle(t(ja: "設定", en: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            t(
                ja: "プロモードを有効にしますか？",
                en: "Enable Pro Mode?"
            ),
            isPresented: $showProModeWarning
        ) {
            Button(t(ja: "有効化", en: "Enable"), role: .destructive) {
                isProModeEnabled = pendingProModeEnabled
                if !modelManager.siglipInstalled {
                    showSigLIPRequirementInfo = true
                }
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {
                pendingProModeEnabled = false
            }
        } message: {
            Text(
                t(
                    ja: "プロモードでは、自分が投稿した元画像のキャッシュがアプリ内にこれまで以上に残ります。意味類似度の評価に加え、処理時間とメモリ使用量の表示にも使われます。メモリ値は処理完了時点のフットプリントです。",
                    en: "In Pro Mode, cached originals for images you post will remain in the app for longer and will be used for semantic similarity scoring and performance readouts. Memory is shown as the footprint at completion."
                )
            )
        }
        .alert(
            t(
                ja: "画像キャッシュを削除しますか？",
                en: "Clear image cache?"
            ),
            isPresented: $showCacheMaintenanceConfirm
        ) {
            Button(t(ja: "削除する", en: "Clear"), role: .destructive) {
                NotificationCenter.default.post(name: .semanticCacheMaintenanceRequested, object: nil)
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "再生成画像キャッシュを削除し、プロモードで保持していた元画像キャッシュと意味スコアも消去します。表示中の投稿画像は必要に応じて再生成されます。",
                    en: "This deletes regenerated image cache and also removes retained originals and semantic scores from Pro Mode. Visible post images will regenerate again if needed."
                )
            )
        }
        .alert(
            t(
                ja: "SigLIP2 モデルが必要です",
                en: "SigLIP2 is required"
            ),
            isPresented: $showSigLIPRequirementInfo
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "プロモードは有効化されましたが、意味保持率の計算には SigLIP2 のインストールが必要です。",
                    en: "Pro Mode is enabled, but SigLIP2 must be installed before semantic fidelity scores can be computed."
                )
            )
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

    private var proModeCacheUsageSummary: String {
        let bytes = ImageCacheManager.shared.totalCacheUsageBytes(in: [.originalImages, .semanticScores])
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
