//
//  ModelInstaller.swift
//  SemanticCompression-v2
//
//  Safe installer for huge model zips (e.g. SD ~4GB)
//  - Range + resume
//  - Chunk write
//  - Correct zip layout for SD (merges.txt / vocab.json)
//

import Foundation
import Combine
import ZIPFoundation

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

    // MARK: - Config

    private let modelURL: URL
    private let modelName: String

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
    private var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Init

    init(modelURL: URL, modelName: String) {
        self.modelURL = modelURL
        self.modelName = modelName

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
        Task {
            do {
                try prepareDirectory()

                if isAlreadyInstalled {
                    status = .completed
                    progress = 1.0
                    return
                }

                status = .downloading
                try await download()

                status = .installing
                try install()

                markInstalled()
                status = .completed
                progress = 1.0

            } catch is CancellationError {
                status = .cancelled
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Download

extension ModelInstaller: URLSessionDataDelegate {

    private func download() async throws {
        expectedTotalSize = try await fetchTotalSize()
        startOffset = currentDownloadedSize()
        receivedThisRun = 0

        totalBytes = expectedTotalSize
        downloadedBytes = startOffset

        if startOffset >= expectedTotalSize {
            try finalizeDownload()
            return
        }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: modelURL)
        if startOffset > 0 {
            request.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
        }

        ensurePartFile()
        openFileHandle()

        let task = session.dataTask(with: request)
        self.task = task

        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            task.resume()
        }

        try finalizeDownload()
    }

    private func fetchTotalSize() async throws -> Int64 {
        var req = URLRequest(url: modelURL)
        req.httpMethod = "HEAD"

        let (_, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse,
              let len = http.value(forHTTPHeaderField: "Content-Length"),
              let size = Int64(len) else {
            throw NSError(domain: "Installer", code: -1)
        }
        return size
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? fileHandle?.write(contentsOf: data)
        receivedThisRun += Int64(data.count)

        let current = startOffset + receivedThisRun
        downloadedBytes = current
        progress = expectedTotalSize > 0
            ? Double(current) / Double(expectedTotalSize)
            : 0
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        closeFileHandle()
        session.invalidateAndCancel()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

// MARK: - Install

extension ModelInstaller {

    private func install() throws {
        // SD のときだけ掃除する
        if modelName.contains("StableDiffusion") {
            let contents = try FileManager.default.contentsOfDirectory(
                at: baseDir,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                let name = url.lastPathComponent

                if name == "model.zip" ||
                   name == "model.zip.part" ||
                   name == ".installed" {
                    continue
                }

                try? FileManager.default.removeItem(at: url)
            }
        }

        #if DEBUG
        print("🟡 [SD] install() start")
        #endif

        guard FileManager.default.fileExists(atPath: zipFileURL.path) else {
            #if DEBUG
            print("🔴 zip not found")
            #endif
            throw NSError(domain: "Installer", code: -20)
        }

        guard let archive = Archive(url: zipFileURL, accessMode: .read) else {
            #if DEBUG
            print("🔴 failed to open zip")
            #endif
            throw NSError(domain: "Installer", code: -21)
        }

        for entry in archive {
            let comps = entry.path.split(separator: "/")
            let normalizedPath: String

            if modelName.contains("StableDiffusion") {
                // SD: トップディレクトリを潰す
                normalizedPath = comps.dropFirst().joined(separator: "/")
            } else {
                // SigLIP2: そのまま
                normalizedPath = entry.path
            }

            guard !normalizedPath.isEmpty else { continue }

            let dst = baseDir.appendingPathComponent(normalizedPath)

            try FileManager.default.createDirectory(
                at: dst.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // 🔑 ZIPFoundation 対策：必ず既存ファイルを消す
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }

            _ = try archive.extract(entry, to: dst)
        }

        #if DEBUG
        print("🟢 [SD] install() completed")
        #endif
        debugPrintDirectory()
    }
}

// MARK: - Files

extension ModelInstaller {

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private func ensurePartFile() {
        if !FileManager.default.fileExists(atPath: partFileURL.path) {
            FileManager.default.createFile(atPath: partFileURL.path, contents: nil)
        }
    }

    private func openFileHandle() {
        fileHandle = try? FileHandle(forWritingTo: partFileURL)
        try? fileHandle?.seekToEnd()
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

    private var isAlreadyInstalled: Bool {
        FileManager.default.fileExists(
            atPath: baseDir.appendingPathComponent(".installed").path
        )
    }

    private func markInstalled() {
        FileManager.default.createFile(
            atPath: baseDir.appendingPathComponent(".installed").path,
            contents: Data()
        )
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
