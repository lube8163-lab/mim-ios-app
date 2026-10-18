//
//  ModelInstaller.swift
//  SemanticCompression-v2
//
//  Safe installer for huge model zips (e.g. SD ~2GB)
//  - Range + resume
//  - Chunk write
//  - Correct zip layout for SD (merges.txt / vocab.json)
//

import Foundation
import Combine
import ZIPFoundation
import CryptoKit

@MainActor
final class ModelInstaller: NSObject, ObservableObject {

    // MARK: - State

    enum Status: Equatable {
        case idle
        case downloading
        case installing
        case completed
        case failed(String)
        case cancelled
    }

    @Published var progress: Double = 0
    @Published var status: Status = .idle
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    private(set) var validatedGenerationAssets: (fingerprint: String, manifest: ModelAssetManifest)?

    // MARK: - Config

    private let modelURL: URL
    private let modelName: String
    private let expectedSHA256: String?
    private let fragments: [ModelDownloadFragment]?
    private let coreAIVision: Bool
    private let generationFamily: PipelineFamily

    // MARK: - Paths

    private let baseDir: URL
    private let partFileURL: URL
    private let zipFileURL: URL

    // MARK: - Download

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?

    private var expectedTotalSize: Int64 = 0
    private var startOffset: Int64 = 0
    private var receivedThisRun: Int64 = 0
    private var fragmentStart: Int64 = 0
    private var fragmentOffset: Int64 = 0
    private var fragmentBytes: Int64 = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var operationTask: Task<Void, Never>?
    private var downloadError: Error?
    private var lastProgressPublication: TimeInterval = 0

    // MARK: - Init

    init(modelURL: URL, modelName: String, expectedSHA256: String? = nil,
         fragments: [ModelDownloadFragment]? = nil, coreAIVision: Bool = false, generationFamily: PipelineFamily = .sd15) {
        self.modelURL = modelURL
        self.modelName = modelName
        self.expectedSHA256 = expectedSHA256?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.fragments = fragments
        self.coreAIVision = coreAIVision
        self.generationFamily = generationFamily

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        self.baseDir = appSupport
            .appendingPathComponent("Models")
            .appendingPathComponent(modelName, isDirectory: true)

        self.partFileURL = baseDir.appendingPathComponent("model.zip.part")
        self.zipFileURL  = baseDir.appendingPathComponent("model.zip")

        super.init()
    }

    // MARK: - Public

    func start() {
        guard operationTask == nil else { return }
        operationTask = Task {
            defer { operationTask = nil }
            do {
                try prepareDirectory()

                if isAlreadyInstalled {
                    removeDownloadedArchives()
                    status = .completed
                    progress = 1.0
                    return
                }

                status = .downloading
                try await download()
                try Task.checkCancellation()
                try await verifyDownloadIfNeeded()

                status = .installing
                try await install()
                try Task.checkCancellation()

                removeDownloadedArchives()
                markInstalled()
                if !coreAIVision && generationFamily == .flux2Klein4B {
                    let root = baseDir
                    validatedGenerationAssets = try await Task.detached(priority: .utility) {
                        (try ModelAssets.inventoryFingerprint(at: root), try CoreAIFluxAssets.catalog())
                    }.value
                }
                status = .completed
                progress = 1.0

            } catch is CancellationError {
                status = .cancelled
            } catch {
                status = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationTask?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        // Publish cancellation only after the operation has drained its file writes.
        if operationTask == nil { status = .cancelled }
    }
}

// MARK: - Download

extension ModelInstaller: @preconcurrency URLSessionDataDelegate {

    private func download() async throws {
        downloadError = nil
        let sources: [ModelDownloadFragment]
        if let fragments { sources = fragments }
        else { sources = [.init(url: modelURL, bytes: try await fetchTotalSize())] }
        let plan = try ModelDownloadPlan(fragments: sources)
        expectedTotalSize = plan.totalBytes
        try Task.checkCancellation()
        if expectedSHA256 != nil,
           (try? zipFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(plan.totalBytes) {
            // A terminated verification must reuse the complete archive, then verify it again.
            totalBytes = plan.totalBytes; downloadedBytes = plan.totalBytes; progress = 1
            return
        }
        startOffset = currentDownloadedSize()
        if startOffset > expectedTotalSize {
            try FileManager.default.removeItem(at: partFileURL)
            startOffset = 0
        }
        receivedThisRun = 0

        totalBytes = expectedTotalSize
        downloadedBytes = startOffset

        if startOffset == expectedTotalSize {
            try finalizeDownload()
            return
        }
        let remaining = try plan.remaining(at: startOffset)
        for source in remaining {
            try Task.checkCancellation()
            fragmentStart = source.start
            fragmentOffset = source.offset
            fragmentBytes = source.fragment.bytes
            startOffset = currentDownloadedSize()
            receivedThisRun = 0
            try await downloadFragment(source.fragment.url)
            guard currentDownloadedSize() == fragmentStart + fragmentBytes else {
                throw URLError(.badServerResponse)
            }
        }
        try finalizeDownload()
    }

    private func downloadFragment(_ url: URL) async throws {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if fragmentOffset > 0 {
            request.setValue("bytes=\(fragmentOffset)-", forHTTPHeaderField: "Range")
        }

        ensurePartFile()
        openFileHandle()

        let task = session.dataTask(with: request)
        self.task = task

        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            task.resume()
        }

    }

    private func fetchTotalSize() async throws -> Int64 {
        if let size = try await fetchTotalSizeByHEAD() {
            return size
        }
        if let size = try await fetchTotalSizeByRangeGET() {
            return size
        }
        throw NSError(
            domain: "Installer",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not determine file size before download"]
        )
    }

    private func fetchTotalSizeByHEAD() async throws -> Int64? {
        var req = URLRequest(url: modelURL)
        req.httpMethod = "HEAD"

        let (_, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else {
            return nil
        }

        return parseSize(from: http)
    }

    private func fetchTotalSizeByRangeGET() async throws -> Int64? {
        var req = URLRequest(url: modelURL)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let (bytes, res) = try await URLSession.shared.bytes(for: req)
        bytes.task.cancel()

        guard let http = res as? HTTPURLResponse,
              http.statusCode == 206 || (200..<300).contains(http.statusCode) else {
            return nil
        }

        return parseSize(from: http)
    }

    private func parseSize(from response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let totalPart = range.split(separator: "/").last,
           let size = Int64(totalPart),
           size > 0 {
            return size
        }

        if let len = response.value(forHTTPHeaderField: "Content-Length"), let size = Int64(len), size > 0 { return size }

        return nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode), status != .cancelled else {
            downloadError = URLError(.badServerResponse)
            completionHandler(.cancel)
            return
        }
        do {
            if http.statusCode == 200 && fragmentOffset > 0 {
                try fileHandle?.truncate(atOffset: UInt64(fragmentStart))
                try fileHandle?.seek(toOffset: UInt64(fragmentStart))
                startOffset = fragmentStart; downloadedBytes = startOffset
                fragmentOffset = 0
            } else if http.statusCode == 206 {
                guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                      range == "bytes \(fragmentOffset)-\(fragmentBytes - 1)/\(fragmentBytes)" else {
                    throw URLError(.badServerResponse)
                }
            }
            if let length = http.value(forHTTPHeaderField: "Content-Length"),
               Int64(length) != fragmentBytes - fragmentOffset { throw URLError(.badServerResponse) }
            completionHandler(.allow)
        } catch { downloadError = error; completionHandler(.cancel) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard status != .cancelled, downloadError == nil else { return }
        do {
            guard startOffset + receivedThisRun + Int64(data.count) <= fragmentStart + fragmentBytes else {
                throw URLError(.badServerResponse)
            }
            guard let fileHandle else { throw CocoaError(.fileWriteUnknown) }
            try fileHandle.write(contentsOf: data)
        } catch { downloadError = error; dataTask.cancel(); return }
        receivedThisRun += Int64(data.count)

        let current = startOffset + receivedThisRun
        publishDownloadProgress(current: current)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        closeFileHandle()
        session.invalidateAndCancel()
        publishDownloadProgress(current: startOffset + receivedThisRun, force: true)

        if let error = downloadError ?? error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }

    private func publishDownloadProgress(current: Int64, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastProgressPublication >= 0.25 else { return }
        lastProgressPublication = now
        downloadedBytes = current
        progress = expectedTotalSize > 0 ? Double(current) / Double(expectedTotalSize) : 0
    }
}

// MARK: - Install

extension ModelInstaller {

    private func install() async throws {
        let archiveURL = zipFileURL
        let destination = baseDir
        let family = generationFamily
        let coreAIVision = self.coreAIVision
        let installation = Task.detached(priority: .utility) {
            if coreAIVision { try ModelArchive.installCoreAIVision(archiveAt: archiveURL, root: destination) }
            else { try ModelArchive.install(archiveAt: archiveURL, root: destination, family: family) }
        }
        try await withTaskCancellationHandler { try await installation.value } onCancel: { installation.cancel() }
    }
}

// MARK: - Files

extension ModelInstaller {

    private func prepareDirectory() throws {
        if !coreAIVision && generationFamily == .flux2Klein4B {
            let parent = baseDir.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let capacity = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            let completeArchive = (try? zipFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(CoreAIFluxAssets.archiveBytes)
            let remaining = completeArchive ? 0 : max(0, CoreAIFluxAssets.archiveBytes - currentDownloadedSize())
            if let capacity, capacity < remaining + CoreAIFluxAssets.installedBytes + 200_000_000 {
                throw RecipeError.invalid("モデルの準備に必要な空き容量が不足しています。約8 GBの空きを確保してください。")
            }
        }
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private func ensurePartFile() {
        if !FileManager.default.fileExists(atPath: partFileURL.path) {
            FileManager.default.createFile(atPath: partFileURL.path, contents: nil)
        }
    }

    private func openFileHandle() {
        fileHandle = try? FileHandle(forWritingTo: partFileURL)
        _ = try? fileHandle?.seekToEnd()
    }

    private func closeFileHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func currentDownloadedSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: partFileURL.path)[.size] as? Int64) ?? 0
    }

    private func finalizeDownload() throws {
        if FileManager.default.fileExists(atPath: zipFileURL.path) {
            try FileManager.default.removeItem(at: zipFileURL)
        }
        try FileManager.default.moveItem(at: partFileURL, to: zipFileURL)
    }

    private func verifyDownloadIfNeeded() async throws {
        guard let expectedSHA256, !expectedSHA256.isEmpty else { return }

        let url = zipFileURL
        let verification = Task.detached(priority: .utility) { try sha256Hex(for: url) }
        let actualSHA256 = try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
        guard actualSHA256 == expectedSHA256 else {
            try? FileManager.default.removeItem(at: zipFileURL)
            try? FileManager.default.removeItem(at: partFileURL)
            throw NSError(
                domain: "Installer",
                code: -33,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Downloaded file verification failed. Expected SHA-256 \(expectedSHA256), got \(actualSHA256)."
                ]
            )
        }
    }

    private var isAlreadyInstalled: Bool {
        if coreAIVision { return CoreAIVisionAssets.installed(at: baseDir) }
        return ModelAssets.requiredFilesExist(at: baseDir, family: generationFamily)
    }

    private func markInstalled() {
        FileManager.default.createFile(
            atPath: baseDir.appendingPathComponent(".installed").path,
            contents: Data()
        )
    }

    private func removeDownloadedArchives() {
        try? FileManager.default.removeItem(at: zipFileURL)
        try? FileManager.default.removeItem(at: partFileURL)
    }

    private func debugPrintDirectory() {
        #if DEBUG
        print("📂 SD dir:", baseDir.path)
        #endif
        let en = FileManager.default.enumerator(at: baseDir, includingPropertiesForKeys: nil)
        while let u = en?.nextObject() as? URL {
            #if DEBUG
            print(" -", u.lastPathComponent)
            #endif
        }
    }
}

nonisolated private func sha256Hex(for fileURL: URL) throws -> String {
    try ModelAssets.fileSHA256(at: fileURL)
}
