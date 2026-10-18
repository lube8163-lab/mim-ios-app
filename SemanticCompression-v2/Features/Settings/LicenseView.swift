import SwiftUI
struct LicenseView: View {
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    var body: some View {
        let _ = language
        List {
            Section(mt("端末内AI")) {
                Text("LFM2.5-VL-450M — LFM Open License 1.0")
                Link(mt("Liquid AIモデルのライセンス"), destination: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-VL-450M/blob/main/LICENSE")!)
                Text(mt("写真の理解: Apple Foundation Models"))
            }
            Section(mt("画像の再現")) {
                Text("FLUX.2 Klein 4B / Qwen3 — Apache 2.0")
                Text(mt("512px・4bitの端末向け変換モデル"))
                Link(mt("Black Forest Labsモデルのライセンス"), destination: URL(string: "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/blob/main/LICENSE.md")!)
                Link(mt("CoreAIモデルの配布元"), destination: URL(string: "https://huggingface.co/dushandz/FLUX.2-klein-4B-CoreAI")!)
                NavigationLink(mt("モデルのライセンスと変更表示")) {
                    ScrollView { Text(modelNotices).font(.footnote).textSelection(.enabled).padding() }
                        .navigationTitle(mt("モデルのライセンスと変更表示"))
                }
            }
            Section(mt("ライブラリ")) {
                Text("ZIPFoundation, swift-transformers, swift-jinja, swift-collections, XGrammar")
                Link("CoreAI Models — BSD 3-Clause", destination: URL(string: "https://github.com/apple/coreai-models")!)
                Link("Apple Stable Diffusion Swift Package", destination: URL(string: "https://github.com/apple/ml-stable-diffusion")!)
                Link("CoreAIKit — BSD 3-Clause", destination: URL(string: "https://github.com/john-rocky/coreai-kit")!)
                NavigationLink(mt("CoreAIランタイムのライセンス")) {
                    ScrollView {
                        Text(runtimeNotices).font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle(mt("CoreAIランタイムのライセンス"))
                }
            }
            Section(mt("画像の安全性")) {
                Text("Image Safety Classifier S — MIT / SwiftFormer — Apache 2.0")
                Link("Image Safety Classifier", destination: URL(string: "https://huggingface.co/OwenElliott/image-safety-classifier-s")!)
                NavigationLink(mt("画像安全性モデルのライセンス")) {
                    ScrollView { Text(safetyNotices).font(.footnote).textSelection(.enabled).padding() }
                        .navigationTitle(mt("画像安全性モデルのライセンス"))
                }
            }
        }.navigationTitle(mt("ライセンス"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(MimStyle.paper)
    }

    private var runtimeNotices: String {
        guard let url = Bundle.main.url(forResource: "CoreAIRuntimeNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return mt("ライセンス本文を読み込めません。") }
        return text
    }
    private var safetyNotices: String {
        guard let url = Bundle.main.url(forResource: "ImageSafetyNotices", withExtension: "txt") else { return mt("ライセンス本文を読み込めません。") }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? mt("ライセンス本文を読み込めません。")
    }
    private var modelNotices: String {
        guard let url = Bundle.main.url(forResource: "ModelLicenseNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return mt("ライセンス本文を読み込めません。") }
        return text
    }
}
