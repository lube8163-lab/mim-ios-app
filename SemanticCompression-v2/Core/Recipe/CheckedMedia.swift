import Foundation

/// Keeps decoding/classification outside this small, testable gate. No sender or UI
/// receives bytes until its injected checker has completed successfully.
@MainActor
enum CheckedMedia {
    static func bytes(_ data: Data, check: (Data) async throws -> Void) async throws -> Data {
        try Task.checkCancellation()
        try await check(data)
        try Task.checkCancellation()
        return data
    }

    static func send<T>(_ data: Data, check: (Data) async throws -> Void,
                        send: (Data) async throws -> T) async throws -> T {
        let checked = try await bytes(data, check: check)
        return try await send(checked)
    }
}
