//
//  LicenseView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/16.
//

import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Group {
                    Text("使用モデル")
                        .font(.headline)

                    Text("""
• SigLIP2
  Copyright © Google LLC
  Licensed under the Apache License, Version 2.0.
  https://www.apache.org/licenses/LICENSE-2.0


• Stable Diffusion v1.5
  License: CreativeML Open RAIL-M
  https://huggingface.co/spaces/CompVis/stable-diffusion-license
""")
                }

                Group {
                    Text("ライセンスについて")
                        .font(.headline)

                    Text("""
本アプリは、各モデルのライセンス条件を遵守し、
オンデバイス処理またはユーザー操作を起点とした生成のみを行います。

生成結果はモデル提供元によって保証されるものではありません。

This app complies with the licenses of all models used.
All generation is performed on-device or initiated by explicit user actions.
Generated results are not endorsed or guaranteed by the model providers.
""")
                }
            }
            .padding()
        }
        .navigationTitle("ライセンス")
    }
}
