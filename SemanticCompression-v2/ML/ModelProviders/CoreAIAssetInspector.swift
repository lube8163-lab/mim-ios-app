import Foundation

nonisolated enum CoreAIRuntimeSupport {
    static var availability: ProviderAvailability {
        #if canImport(CoreAI)
        if #available(iOS 27.0, macOS 27.0, *) { return .coreAI(sdkAvailable: true) }
        #endif
        return .coreAI(sdkAvailable: false)
    }
}

nonisolated struct CoreAIFunctionInspection: Sendable {
    let name: String
    let descriptor: String
}

// Inspection specializes/loads an asset; it does not implement a VLM or diffusion runner.
#if canImport(CoreAI)
import CoreAI

@available(iOS 27.0, macOS 27.0, *)
actor CoreAIAssetInspector {
    func inspect(at assetURL: URL) async throws -> [CoreAIFunctionInspection] {
        guard assetURL.isFileURL, ["aimodel", "aimodelc"].contains(assetURL.pathExtension),
              FileManager.default.fileExists(atPath: assetURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        try Task.checkCancellation()
        let model = try await AIModel(contentsOf: assetURL, options: .default)
        try Task.checkCancellation()
        return model.functionNames.map { name in
            .init(name: name, descriptor: String(describing: model.functionDescriptor(for: name)))
        }
    }
}
#endif
