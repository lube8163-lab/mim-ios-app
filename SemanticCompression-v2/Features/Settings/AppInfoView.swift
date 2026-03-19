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
                    titleZH: "应用概览",
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
                    """,
                    bodyZH: """
                    本应用是一个实验性的社交平台。它不会总是直接保存和分享原始图片，
                    而是尝试把图像视为语义信息或压缩表示，并在需要时于设备端重建。

                    发帖时，图像理解模型可以生成 caption、prompt 和 tags。
                    浏览时，图像生成模型可以在设备上重建时间线图片。
                    """
                )

                infoSection(
                    titleJA: "画像理解モデル",
                    titleEN: "Image Understanding Models",
                    titleZH: "图像理解模型",
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
                    """,
                    bodyZH: """
                    SigLIP2:
                    这是一个轻量级流程，会提取标签和视觉特征，再组合生成 caption 和 prompt。
                    在专业模式下，它也会用于计算与重建图像之间的语义保持率。

                    Qwen3.5-VL-0.8B:
                    直接从图像生成 caption、prompt 和 tags。
                    它比 SigLIP2 更重，但有时能给出更具上下文的描述。

                    如果两个模型都未安装：
                    图片帖子将无法执行图像理解，因此不能进行基于图片的语义发布。
                    需要时仍可发布纯文本内容。
                    """
                )

                infoSection(
                    titleJA: "画像生成モデル",
                    titleEN: "Image Generation Models",
                    titleZH: "图像生成模型",
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
                    """,
                    bodyZH: """
                    Stable Diffusion 1.5:
                    用于在时间线和帖子列表中生成重建图像。
                    由于支持基于原图的 img2img 流程，因此更适合做质量优先的比较与确认。

                    Stable Diffusion 1.5 (LCM):
                    面向更快的重建速度。它比标准模型更快，但不使用 img2img 风格的流程。

                    如果未安装图像生成模型：
                    将不会显示重建图像，帖子主要以文本和生成的 caption 形式查看。
                    """
                )

                infoSection(
                    titleJA: "投稿モード",
                    titleEN: "Post Modes",
                    titleZH: "发布模式",
                    bodyJA: """
                    投稿モードでは、どの程度元画像に近い情報を残すかを選べます。
                    軽いモードほど保護寄りになり、高いモードほど再構成しやすくなります。

                    生成結果や再構成品質は、選択したモード、利用中モデル、元画像の内容によって変わります。
                    """,
                    bodyEN: """
                    Post modes control how much image-derived information is preserved.
                    Lighter modes favor privacy, while stronger modes allow easier reconstruction.

                    Reconstruction quality depends on the selected mode, the active model, and the content of the original image.
                    """,
                    bodyZH: """
                    发布模式决定会保留多少来自原图的信息。
                    越轻的模式越偏向隐私保护，越强的模式越容易重建。

                    重建质量取决于所选模式、当前使用的模型以及原图内容。
                    """
                )

                infoSection(
                    titleJA: "プロモード",
                    titleEN: "Pro Mode",
                    titleZH: "专业模式",
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
                    """,
                    bodyZH: """
                    专业模式会为你自己的帖子显示语义保持率评分，用于比较原图与重建图像之间的差异。
                    同时也会显示 prompt 生成时间、图像生成时间以及内存使用量。

                    这些读数主要用于比较和评估。
                    内存显示的不是峰值，而是每一步完成时测得的占用。

                    计算语义保持率需要 SigLIP2。
                    你也可以在设置中按需调整缓存上限。
                    """
                )

                Text(
                    t(
                        ja: "生成結果は研究用途の参考出力であり、モデル提供元によって保証・推奨されるものではありません。",
                        en: "Generated outputs are experimental reference results and are not endorsed or guaranteed by model providers.",
                        zh: "生成结果仅供研究和实验参考，不代表模型提供方的保证或推荐。"
                    )
                )

                Text(t(ja: "リンク", en: "Links", zh: "链接"))
                    .font(.headline)

                Link(
                    "GitHub Repository",
                    destination: URL(string: "https://github.com/lube8163-lab/mim-ios/tree/main")!
                )
            }

            .padding()
        }
        .navigationTitle(t(ja: "アプリの説明", en: "App Info", zh: "应用说明"))
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }

    @ViewBuilder
    private func infoSection(
        titleJA: String,
        titleEN: String,
        titleZH: String,
        bodyJA: String,
        bodyEN: String,
        bodyZH: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t(ja: titleJA, en: titleEN, zh: titleZH))
                .font(.headline)
            Text(t(ja: bodyJA, en: bodyEN, zh: bodyZH))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
