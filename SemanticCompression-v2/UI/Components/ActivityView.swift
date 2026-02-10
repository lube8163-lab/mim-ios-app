//
//  ActivityView.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/10.
//


import UIKit
import SwiftUI

struct ActivityView: UIViewControllerRepresentable {

    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
