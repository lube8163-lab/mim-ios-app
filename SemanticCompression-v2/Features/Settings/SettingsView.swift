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
            Section(t(ja: "一般", en: "General", zh: "通用")) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Text(t(ja: "言語設定", en: "Language", zh: "语言"))
                }

                NavigationLink {
                    PrivacyModeSettingsView()
                } label: {
                    Text(t(ja: "投稿モード", en: "Post Mode", zh: "发布模式"))
                }
            }

            Section(t(ja: "プロ機能", en: "Pro Features", zh: "专业功能")) {
                Toggle(isOn: proModeBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(ja: "プロモード", en: "Pro Mode", zh: "专业模式"))
                        Text(
                            t(
                                ja: "自分の投稿画像の元画像キャッシュを保持し、再生成結果との意味類似度に加えて、処理時間とメモリ使用量も表示します。メモリ値は処理完了時点のフットプリントです。",
                                en: "Keep original-image cache for your posts and show semantic similarity, processing time, and memory usage for regenerated results. Memory is shown as the footprint at completion.",
                                zh: "为你自己的帖子保留原图缓存，并显示与重建结果的语义相似度、处理时间和内存使用量。内存值显示的是每一步完成时的占用。"
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
                            Text(t(ja: "画像キャッシュを削除", en: "Clear Image Cache", zh: "清除图片缓存"))
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }

                    Text(
                        t(
                            ja: "この操作で再生成キャッシュを削除します。プロモードで保持した元画像キャッシュと意味スコアも削除されます。",
                            en: "This clears regenerated image cache. It also removes retained originals and semantic scores created by Pro Mode.",
                            zh: "此操作会清除重建图片缓存，也会删除专业模式保留的原图缓存和语义评分。"
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if !modelManager.siglipInstalled {
                        Text(
                            t(
                                ja: "意味保持率の計算には SigLIP2 モデルが必要です。未導入でもプロモードは有効化できますが、スコアは表示されません。",
                                en: "SigLIP2 is required for semantic fidelity scoring. You can enable Pro Mode without it, but scores will stay unavailable.",
                                zh: "计算语义保持率需要 SigLIP2 模型。即使未安装也可以开启专业模式，但不会显示评分。"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                    }

                        Text(
                            t(
                                ja: "メモリ使用量はピーク値ではなく、各処理が終わった時点のフットプリントです。",
                                en: "Memory usage is not a peak reading. It is the footprint measured when each step finishes.",
                                zh: "内存使用量不是峰值，而是每个处理步骤完成时的占用。"
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Stepper(value: $proModeCacheLimitMB, in: 50...1000, step: 50) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                t(
                                    ja: "プロモードのキャッシュ上限: \(proModeCacheLimitMB) MB",
                                    en: "Pro Mode cache limit: \(proModeCacheLimitMB) MB",
                                    zh: "专业模式缓存上限：\(proModeCacheLimitMB) MB"
                                )
                            )
                            Text(
                                t(
                                    ja: "使用中: \(proModeCacheUsageSummary)",
                                    en: "In use: \(proModeCacheUsageSummary)",
                                    zh: "已使用：\(proModeCacheUsageSummary)"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(t(ja: "このアプリについて", en: "About", zh: "关于本应用")) {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(t(ja: "アプリの説明", en: "App Info", zh: "应用说明"))
                }
            }

            Section(t(ja: "法務", en: "Legal", zh: "法律")) {
                NavigationLink {
                    LegalDocumentsView()
                } label: {
                    Text(t(ja: "プライバシーポリシー / 利用規約", en: "Privacy Policy / Terms", zh: "隐私政策 / 使用条款"))
                }
            }

            Section(t(ja: "ライセンス", en: "Licenses", zh: "许可证")) {
                NavigationLink {
                    LicenseView()
                } label: {
                    Text(t(ja: "使用モデルとライセンス", en: "Models and Licenses", zh: "模型与许可证"))
                }
            }
        }
        .navigationTitle(t(ja: "設定", en: "Settings", zh: "设置"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            t(
                ja: "プロモードを有効にしますか？",
                en: "Enable Pro Mode?",
                zh: "要启用专业模式吗？"
            ),
            isPresented: $showProModeWarning
        ) {
            Button(t(ja: "有効化", en: "Enable", zh: "启用"), role: .destructive) {
                isProModeEnabled = pendingProModeEnabled
                if !modelManager.siglipInstalled {
                    showSigLIPRequirementInfo = true
                }
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {
                pendingProModeEnabled = false
            }
        } message: {
            Text(
                t(
                    ja: "プロモードでは、自分が投稿した元画像のキャッシュがアプリ内にこれまで以上に残ります。意味類似度の評価に加え、処理時間とメモリ使用量の表示にも使われます。メモリ値は処理完了時点のフットプリントです。",
                    en: "In Pro Mode, cached originals for images you post will remain in the app for longer and will be used for semantic similarity scoring and performance readouts. Memory is shown as the footprint at completion.",
                    zh: "在专业模式下，你发布图片的原图缓存会在应用内保留更久，并用于语义相似度评分与性能信息显示。内存值显示的是处理完成时的占用。"
                )
            )
        }
        .alert(
            t(
                ja: "画像キャッシュを削除しますか？",
                en: "Clear image cache?",
                zh: "要清除图片缓存吗？"
            ),
            isPresented: $showCacheMaintenanceConfirm
        ) {
            Button(t(ja: "削除する", en: "Clear", zh: "清除"), role: .destructive) {
                NotificationCenter.default.post(name: .semanticCacheMaintenanceRequested, object: nil)
            }
            Button(t(ja: "キャンセル", en: "Cancel", zh: "取消"), role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "再生成画像キャッシュを削除し、プロモードで保持していた元画像キャッシュと意味スコアも消去します。表示中の投稿画像は必要に応じて再生成されます。",
                    en: "This deletes regenerated image cache and also removes retained originals and semantic scores from Pro Mode. Visible post images will regenerate again if needed.",
                    zh: "这会删除重建图片缓存，也会清除专业模式保留的原图缓存和语义评分。当前可见的帖子图片会在需要时重新生成。"
                )
            )
        }
        .alert(
            t(
                ja: "SigLIP2 モデルが必要です",
                en: "SigLIP2 is required",
                zh: "需要 SigLIP2 模型"
            ),
            isPresented: $showSigLIPRequirementInfo
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "プロモードは有効化されましたが、意味保持率の計算には SigLIP2 のインストールが必要です。",
                    en: "Pro Mode is enabled, but SigLIP2 must be installed before semantic fidelity scores can be computed.",
                    zh: "专业模式已启用，但要计算语义保持率仍需先安装 SigLIP2。"
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

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
