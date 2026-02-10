//
//  RainbowAILoader.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/30.
//


import SwiftUI

struct RainbowAILoader: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.1, to: 1.0)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .red, .orange, .yellow,
                        .green, .cyan, .blue,
                        .purple, .red
                    ]),
                    center: .center
                ),
                style: StrokeStyle(
                    lineWidth: 6,
                    lineCap: .round
                )
            )
            .frame(width: 36, height: 36)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.0)
                        .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}

