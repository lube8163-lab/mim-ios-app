import UIKit

@MainActor
final class SemanticExtractionTask {
    static let shared = SemanticExtractionTask()
    func describe(_ image: UIImage, provider: UnderstandingProviderID) async throws -> PhotoUnderstandingOutput {
        let manager = ModelManager.shared
        try await manager.beginUnderstandingWhenAvailable()
        defer { manager.endUnderstanding() }
        let started = ProcessInfo.processInfo.systemUptime
        try await ImageSafetyService.check(image)
        let safetySeconds = ProcessInfo.processInfo.systemUptime - started
        let selected = PhotoProviderRegistry.understanding(provider)
        try selected.availability.requireReady()
        var result = try await selected.analyze(image)
        let contentPolicy = try ContentSafetyPolicy.bundled()
        try contentPolicy.validate(result.scene.description)
        try contentPolicy.validate(result.scene.subjects.joined(separator: " "))
        result = .init(scene: result.scene, identity: result.identity, processedSize: result.processedSize,
            measurements: .init(preparationSeconds: (result.measurements.preparationSeconds ?? 0) + max(0, safetySeconds),
                inferenceSeconds: result.measurements.inferenceSeconds,
                elapsedSeconds: ProcessInfo.processInfo.systemUptime - started,
                elapsedScope: "On-device input image safety classification, followed by " + (result.measurements.elapsedScope ?? "photo understanding")),
            fallbackReason: result.fallbackReason)
        return result
    }
}
