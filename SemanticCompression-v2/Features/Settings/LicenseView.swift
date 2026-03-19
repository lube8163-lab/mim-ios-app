//
//  LicenseView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct LicenseView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Group {
                    Text(t(ja: "使用モデル", en: "Models Used", zh: "使用模型"))
                        .font(.headline)

                    Text(t(
                        ja: """
• SigLIP2
  Copyright © Google LLC
  Licensed under the Apache License, Version 2.0.
  https://www.apache.org/licenses/LICENSE-2.0


• Qwen3.5-VL-0.8B
  Copyright © Alibaba Cloud / Qwen
  License: See upstream distribution terms.
  https://huggingface.co/Qwen


• Stable Diffusion v1.5
  License: CreativeML Open RAIL-M
  https://huggingface.co/spaces/CompVis/stable-diffusion-license
""",
                        en: """
• SigLIP2
  Copyright © Google LLC
  Licensed under the Apache License, Version 2.0.
  https://www.apache.org/licenses/LICENSE-2.0


• Qwen3.5-VL-0.8B
  Copyright © Alibaba Cloud / Qwen
  License: See upstream distribution terms.
  https://huggingface.co/Qwen


• Stable Diffusion v1.5
  License: CreativeML Open RAIL-M
  https://huggingface.co/spaces/CompVis/stable-diffusion-license
""",
                        zh: """
• SigLIP2
  版权所有 © Google LLC
  采用 Apache License 2.0。
  https://www.apache.org/licenses/LICENSE-2.0


• Qwen3.5-VL-0.8B
  版权所有 © Alibaba Cloud / Qwen
  许可：请参阅上游分发条款。
  https://huggingface.co/Qwen


• Stable Diffusion v1.5
  许可：CreativeML Open RAIL-M
  https://huggingface.co/spaces/CompVis/stable-diffusion-license
"""
                    ))
                }

                Group {
                    Text(t(ja: "ライセンスについて", en: "About Licenses", zh: "关于许可证"))
                        .font(.headline)

                    Text(t(
                        ja: """
本アプリは、各モデルのライセンス条件を遵守し、
オンデバイス処理またはユーザー操作を起点とした生成のみを行います。

生成結果はモデル提供元によって保証されるものではありません。
""",
                        en: """
This app complies with the licenses of all models used.
All generation is performed on-device or initiated by explicit user actions.
Generated results are not endorsed or guaranteed by the model providers.
""",
                        zh: """
本应用遵守所使用各模型的许可证条款。
所有生成均在设备端执行，或由用户明确操作触发。
生成结果不代表模型提供方的保证或认可。
"""
                    ))
                }
            }
            .padding()
        }
        .navigationTitle(t(ja: "ライセンス", en: "Licenses", zh: "许可证"))
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
