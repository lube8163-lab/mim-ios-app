//
//  AppInfoView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct AppInfoView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                Text("Semantic Compression")
                    .font(.title2)
                    .bold()

                infoSection(
                    titleJA: "このアプリについて",
                    titleEN: "Overview",
                    bodyJA: """
                    このアプリは、画像をそのまま保存・共有するのではなく、意味情報や圧縮表現として扱い、
                    必要に応じて端末上で再構成することを試す研究・実験的なSNSアプリです。

                    投稿時には画像理解モデルで caption / prompt / tags を生成し、
                    閲覧時には画像生成モデルで再構成画像を表示できます。
                    """,
                    bodyEN: """
                    This app is an experimental social network that treats images as semantic or compressed representations
                    instead of always storing and sharing the original image data.

                    At post time, image understanding models can generate captions, prompts, and tags.
                    At viewing time, image generation models can reconstruct timeline images on-device.
                    """
                )

                infoSection(
                    titleJA: "画像理解モデル",
                    titleEN: "Image Understanding Models",
                    bodyJA: """
                    SigLIP2:
                    画像からタグや特徴量を抽出し、比較的軽量に caption / prompt を組み立てます。
                    プロモードでは、再生成画像との意味保持率評価にも使われます。

                    Qwen3.5-VL-0.8B:
                    画像から caption / prompt / tags を直接生成します。
                    SigLIP2 より重い一方、より文脈的で自然な説明になる場合があります。

                    どちらも未インストールの場合:
                    画像付き投稿では画像理解処理を行えないため、画像を使った意味投稿はできません。
                    必要に応じてテキストのみ投稿できます。
                    """,
                    bodyEN: """
                    SigLIP2:
                    Extracts tags and visual features, then builds captions and prompts with a lightweight pipeline.
                    In Pro Mode, it is also used to score semantic fidelity against regenerated images.

                    Qwen3.5-VL-0.8B:
                    Directly generates captions, prompts, and tags from the image.
                    It is heavier than SigLIP2, but can produce more contextual descriptions.

                    If neither is installed:
                    Image understanding cannot run for image posts, so semantic image posting is unavailable.
                    You can still post text-only content when needed.
                    """
                )

                infoSection(
                    titleJA: "画像生成モデル",
                    titleEN: "Image Generation Models",
                    bodyJA: """
                    Stable Diffusion 1.5:
                    タイムラインや投稿一覧で再構成画像を生成します。
                    元画像ベースの img2img を使えるため、品質重視の比較や確認に向いています。

                    Stable Diffusion 1.5 (LCM):
                    高速な再構成向けです。通常モデルより速い一方、img2img ベースの挙動は使いません。

                    画像生成モデルが未インストールの場合:
                    再構成画像は表示されず、テキストや caption のみを確認する形になります。
                    """,
                    bodyEN: """
                    Stable Diffusion 1.5:
                    Generates reconstructed images for the timeline and post lists.
                    Because it supports the starting-image img2img workflow, it is better suited for quality-focused comparisons.

                    Stable Diffusion 1.5 (LCM):
                    Optimized for faster reconstruction. It is faster than the standard model, but does not use the img2img-style workflow.

                    If no image generation model is installed:
                    Reconstructed images are not shown, and posts are viewed mainly through text and generated captions.
                    """
                )

                infoSection(
                    titleJA: "投稿モード",
                    titleEN: "Post Modes",
                    bodyJA: """
                    投稿モードでは、どの程度元画像に近い情報を残すかを選べます。
                    軽いモードほど保護寄りになり、高いモードほど再構成しやすくなります。

                    生成結果や再構成品質は、選択したモード、利用中モデル、元画像の内容によって変わります。
                    """,
                    bodyEN: """
                    Post modes control how much image-derived information is preserved.
                    Lighter modes favor privacy, while stronger modes allow easier reconstruction.

                    Reconstruction quality depends on the selected mode, the active model, and the content of the original image.
                    """
                )

                infoSection(
                    titleJA: "プロモード",
                    titleEN: "Pro Mode",
                    bodyJA: """
                    プロモードでは、自分の投稿に対して再生成画像との意味保持率を表示できます。
                    あわせて、prompt 生成時間、画像生成時間、メモリ使用量も確認できます。

                    これらの表示は比較や検証をしやすくするためのもので、
                    メモリ値はピークではなく、各処理が完了した時点のフットプリントです。

                    意味保持率の計算には SigLIP2 が必要です。
                    必要に応じて設定画面からキャッシュ容量を調整できます。
                    """,
                    bodyEN: """
                    Pro Mode shows a semantic fidelity score for your own posts by comparing regenerated images with the original.
                    It also exposes prompt-generation time, image-generation time, and memory usage for inspection.

                    These readouts are intended for comparison and evaluation.
                    Memory is shown as the footprint measured when each step completes, not as a peak value.

                    SigLIP2 is required for semantic fidelity scoring.
                    You can also adjust the cache budget from Settings when needed.
                    """
                )

                Text(
                    t(
                        ja: "生成結果は研究用途の参考出力であり、モデル提供元によって保証・推奨されるものではありません。",
                        en: "Generated outputs are experimental reference results and are not endorsed or guaranteed by model providers."
                    )
                )

                Text(t(ja: "リンク", en: "Links"))
                    .font(.headline)

                Link(
                    "GitHub Repository",
                    destination: URL(string: "https://github.com/lube8163-lab/mim-ios/tree/main")!
                )
            }

            .padding()
        }
        .navigationTitle(t(ja: "アプリの説明", en: "App Info"))
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }

    @ViewBuilder
    private func infoSection(titleJA: String, titleEN: String, bodyJA: String, bodyEN: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t(ja: titleJA, en: titleEN))
                .font(.headline)
            Text(t(ja: bodyJA, en: bodyEN))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
