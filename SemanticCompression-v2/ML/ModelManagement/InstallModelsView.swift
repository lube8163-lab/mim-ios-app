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

    var body: some View {
        VStack(spacing: 24) {

            // MARK: - Title
            Text("AIモデルのインストール")
                .font(.largeTitle.bold())
                .padding(.top, 40)

            // MARK: - Description
            Text("""
画像生成（Stable Diffusion）や画像解析（SigLIP2）を利用するには、
AIモデルのダウンロードが必要です。

必要なモデルは後から個別にインストールできます。
""")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // MARK: - Install Content（分離UI）
            ModelInstallContentView(
                modelManager: modelManager
            )
            .frame(maxHeight: 460)
            
            if modelManager.siglipInstalled || modelManager.sdInstalled {
                Text("""
※ モデルのインストール完了後は、
アプリを一度終了して再起動してください。
""")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            // MARK: - Skip Button
            if !modelManager.siglipInstalling &&
               !modelManager.sdInstalling &&
               !modelManager.siglipInstalled &&
               !modelManager.sdInstalled {

                Button {
                    dismiss()
                } label: {
                    Text("今はスキップ")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
        .padding()
        // インストール中は閉じさせない
        .interactiveDismissDisabled(
            modelManager.siglipInstalling || modelManager.sdInstalling
        )
    }
}

#Preview {
    InstallModelsView(modelManager: ModelManager.shared)
}
