//
//  TaggerHolder.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/08.
//


import Foundation
import Combine

@MainActor
final class TaggerHolder: ObservableObject {

    let objectTagger = EmbeddingTagger()
    let captionTagger = EmbeddingTagger()
    let styleTagger = EmbeddingTagger()

    func loadAll() {
        let resourceDirectory = ModelManager.shared.siglipResourceDirectory

        objectTagger.loadEmbeddings(
            labelFile: "tag_labels_siglip2_base",
            embeddingFile: "tag_embs_siglip2_base",
            resourceDirectory: resourceDirectory
        )

        captionTagger.loadEmbeddings(
            labelFile: "caption_10k",
            embeddingFile: "caption_10k_embs",
            resourceDirectory: resourceDirectory
        )

        styleTagger.loadEmbeddings(
            labelFile: "styles",
            embeddingFile: "styles_embs",
            resourceDirectory: resourceDirectory
        )
    }
}
