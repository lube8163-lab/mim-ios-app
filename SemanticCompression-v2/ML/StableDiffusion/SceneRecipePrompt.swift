import Foundation
import StableDiffusion

@MainActor
enum SceneRecipePrompt {
    static func build(_ scene: PhotoSceneDescription, manifest: ModelAssetManifest, resources: URL?) throws -> String {
        let policy = try PromptPolicy.bundled()
        try policy.validate(prompt: scene.generationPrompt + " " + scene.description)
        if manifest.family == .flux2Klein4B {
            let prompt = try ScenePromptBuilder.flux(prompt: scene.generationPrompt, counts: scene.counts,
                arrangement: scene.arrangement, relationships: scene.relationships, colors: scene.colors,
                background: scene.background, lighting: scene.lighting, medium: scene.medium)
            try policy.validate(prompt: prompt)
            return prompt
        }
        if manifest.family == .sanaSprint06B { return scene.generationPrompt }
        let merges = resources?.appendingPathComponent("merges.txt")
            ?? Bundle.main.url(forResource: "sd15-merges", withExtension: "txt")
        let vocabulary = resources?.appendingPathComponent("vocab.json")
            ?? Bundle.main.url(forResource: "sd15-vocab", withExtension: "json")
        guard let merges, let vocabulary, resources != nil || manifest.family == .sd15 else { throw RecipeError.modelMismatch }
        let tokenizer = try BPETokenizer(mergesAt: merges, vocabularyAt: vocabulary)
        return try ScenePromptBuilder.build(prompt: scene.generationPrompt, subjects: scene.subjects,
            counts: scene.counts, arrangement: scene.arrangement, relationships: scene.relationships,
            colors: scene.colors, background: scene.background, lighting: scene.lighting, medium: scene.medium,
            maximumTokens: 77, tokenCount: { tokenizer.tokenize(input: $0).tokenIDs.count })
    }
}
