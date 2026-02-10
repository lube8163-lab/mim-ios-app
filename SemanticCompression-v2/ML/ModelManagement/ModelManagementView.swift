//
//  ModelManagementView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/17.
//

import SwiftUI

struct ModelManagementView: View {

    @StateObject private var modelManager = ModelManager()

    var body: some View {
        ModelInstallContentView(
            modelManager: modelManager
        )
        .onAppear {
            modelManager.reloadState()
        }
    }
}
