// Bounded cache scoped to one immutable model pipeline.
// Retains CPU Float conditioning, never the heavy text encoder or a generated image.
#if canImport(CoreAI) && !targetEnvironment(simulator)
actor FluxSpeedTextCache {
    private var entries: [String: [Float]] = [:]
    private var order: [String] = []

    func get(_ text: String) -> [Float]? {
        entries[text]
    }

    func set(_ text: String, embeddings: [Float]) {
        if entries[text] == nil { order.append(text) }
        entries[text] = embeddings
        if order.count > 3 { entries.removeValue(forKey: order.removeFirst()) }
    }
}

enum FluxPromptError: Error { case tooManyTokens }

#endif
