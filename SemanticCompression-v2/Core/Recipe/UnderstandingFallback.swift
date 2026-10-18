import Foundation

@MainActor
enum UnderstandingFallback {
    static func run<Result>(primaryAvailability: ProviderAvailability,
                            fallbackAvailability: ProviderAvailability,
                            primary: () async throws -> Result,
                            fallback: () async throws -> Result) async throws -> (result: Result, reason: String?) {
        try Task.checkCancellation()
        let reason: String
        if primaryAvailability.canRun {
            do { return (try await primary(), nil) }
            catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                reason = error.localizedDescription
            }
        } else { reason = primaryAvailability.message }
        try Task.checkCancellation()
        try fallbackAvailability.requireReady()
        return (try await fallback(), reason)
    }
}
