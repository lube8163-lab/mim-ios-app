//
//  EmbeddingTagger.swift
//  SemanticCompression-v2
//
//  SigLIP2 embedding → semantic tags (top-K)
//  テストアプリの仕様（JSON + NPY）に準拠しつつ
//  semanticcompression-v2 で安全に動作する形に再構築。
//

import Foundation
import Accelerate

final class EmbeddingTagger {

    private var labels: [String] = []
    private var vectors: [[Float]] = []
    private var dimension: Int = 0

    // MARK: - Load Dictionary (call once at app start)
    func loadEmbeddings(labelFile: String, embeddingFile: String, resourceDirectory: URL? = nil) {
        do {
            // ---- Load labels (.json)
            guard
                let url1 = resolveResourceURL(
                    directory: resourceDirectory,
                    fileName: labelFile,
                    fileExtension: "json"
                )
            else {
                #if DEBUG
                print("❌ EmbeddingTagger: label JSON not found.")
                #endif
                return
            }

            let data = try Data(contentsOf: url1)
            labels = try JSONDecoder().decode([String].self, from: data)

            // ---- Load embeddings (.npy)
            guard
                let url2 = resolveResourceURL(
                    directory: resourceDirectory,
                    fileName: embeddingFile,
                    fileExtension: "npy"
                )
            else {
                #if DEBUG
                print("❌ EmbeddingTagger: embedding npy not found.")
                #endif
                return
            }

            let npArr = try NumpyLoader.loadNpy(from: url2)

            let rows = npArr.shape[0]
            let cols = npArr.shape[1]
            dimension = cols

            vectors = []

            for r in 0..<rows {
                let start = r * cols
                let end = start + cols
                let vec = Array(npArr.data[start..<end])
                vectors.append(vec)
            }
            
            #if DEBUG
            print("📚 EmbeddingTagger loaded: \(labels.count) tags, dim=\(dimension)")
            #endif

        } catch {
            #if DEBUG
            print("❌ EmbeddingTagger load error:", error.localizedDescription)
            #endif
        }
    }

    private func resolveResourceURL(
        directory: URL?,
        fileName: String,
        fileExtension: String
    ) -> URL? {
        if let directory {
            let candidate = directory.appendingPathComponent("\(fileName).\(fileExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    }

    // MARK: - Top-K Tag Extraction
    func tags(from embedding: [Float], topK: Int = 5) -> [String] {

        guard !labels.isEmpty, !vectors.isEmpty else {
            #if DEBUG
            print("⚠️ EmbeddingTagger: dictionary not loaded.")
            #endif
            return []
        }

        let normA = l2norm(embedding)

        var scored: [(String, Float)] = []
        scored.reserveCapacity(labels.count)

        for i in 0..<labels.count {
            let score = cosine(a: embedding, b: vectors[i], normA: normA)
            scored.append((labels[i], score))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }

    // MARK: - Cosine Similarity (Accelerate)
    private func cosine(a: [Float], b: [Float], normA: Float) -> Float {
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        var normB: Float = 0
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        normB = sqrt(normB)

        return dot / (normA * normB + 1e-6)
    }

    private func l2norm(_ v: [Float]) -> Float {
        var result: Float = 0
        vDSP_svesq(v, 1, &result, vDSP_Length(v.count))
        return sqrt(result)
    }
}
