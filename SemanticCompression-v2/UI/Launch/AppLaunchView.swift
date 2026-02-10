//
//  AppLaunchView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2026/01/05.
//


import SwiftUI

struct AppLaunchView: View {
    var body: some View {
        VStack(spacing: 28) {

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)

            Text("Preparing AI models…")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
