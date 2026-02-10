import Foundation
import Combine

@MainActor
final class ModelManager: ObservableObject {

    static let shared = ModelManager()
    private var cancellables = Set<AnyCancellable>()

    private var siglipInstaller: ModelInstaller?
    private var sdInstaller: ModelInstaller?

    // MARK: - Manifest Types

    struct ModelManifest: Decodable {
        let models: [ModelEntry]
    }

    struct ModelEntry: Decodable {
        let id: String
        let name: String
        let version: String
        let sizeMB: Int
        let installPath: String
        let zip: ZipInfo
    }

    struct ZipInfo: Decodable {
        let url: String
        let sha256: String
    }

    // MARK: - Published

    @Published var siglipInstalled = false
    @Published var sdInstalled = false

    @Published var siglipInstalling = false
    @Published var sdInstalling = false

    @Published var siglipProgress: Double = 0
    @Published var sdProgress: Double = 0

    @Published var siglipDownloadedBytes: Int64 = 0
    @Published var siglipTotalBytes: Int64 = 0

    @Published var sdDownloadedBytes: Int64 = 0
    @Published var sdTotalBytes: Int64 = 0

    var isModelInstalled: Bool {
        siglipInstalled && sdInstalled
    }

    // MARK: - Paths

    static var modelsRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("Models")
    }

    // MARK: - Init

    init() {
        reloadState()
    }

    // MARK: - Installed Check

    private func isInstalled(path: String) -> Bool {
        let marker = Self.modelsRoot
            .appendingPathComponent(path)
            .appendingPathComponent(".installed")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    func reloadState() {
        siglipInstalled = isInstalled(path: "SigLIP2")
        sdInstalled     = isInstalled(path: "StableDiffusion/sd15")
    }

    // MARK: - Install

    func installSigLIP() {

        guard !siglipInstalling else { return }

        siglipInstalling = true
        siglipProgress = 0.01
        siglipDownloadedBytes = 0
        siglipTotalBytes = 0

        let installer = ModelInstaller(
            modelURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/siglip2/siglip2-vision-v1.zip"
            )!,
            modelName: "SigLIP2"
        )
        siglipInstaller = installer

        // --- progress ---
        installer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.siglipProgress = max(v, 0.01)
            }
            .store(in: &cancellables)

        // --- bytes ---
        installer.$downloadedBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.siglipDownloadedBytes = v
            }
            .store(in: &cancellables)

        installer.$totalBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.siglipTotalBytes = v
            }
            .store(in: &cancellables)

        // --- status（ここが一番重要） ---
        installer.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                switch status {
                case .completed:
                    self.siglipInstalling = false
                    self.siglipProgress = 1.0
                    self.reloadState()

                case .failed, .cancelled:
                    // ❗ 必ず戻す
                    self.siglipInstalling = false

                default:
                    break
                }
            }
            .store(in: &cancellables)

        installer.start()
    }

    func installSD() {

        guard !sdInstalling else { return }

        sdInstalling = true
        sdProgress = 0.01
        sdDownloadedBytes = 0
        sdTotalBytes = 0

        let installer = ModelInstaller(
            modelURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sd15/sd15_coreml.zip"
            )!,
            modelName: "StableDiffusion/sd15"
        )
        sdInstaller = installer

        installer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.sdProgress = max(v, 0.01)
            }
            .store(in: &cancellables)

        installer.$downloadedBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.sdDownloadedBytes = v
            }
            .store(in: &cancellables)

        installer.$totalBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.sdTotalBytes = v
            }
            .store(in: &cancellables)

        installer.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                switch status {
                case .completed:
                    self.sdInstalling = false
                    self.sdProgress = 1.0
                    self.reloadState()

                case .failed, .cancelled:
                    self.sdInstalling = false

                default:
                    break
                }
            }
            .store(in: &cancellables)

        installer.start()
    }

    // MARK: - Delete

    func deleteAllModels() {
        try? FileManager.default.removeItem(at: Self.modelsRoot)
        reloadState()
    }

    // MARK: - Directory

    private func prepareRoot() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.modelsRoot.path) {
            try fm.createDirectory(at: Self.modelsRoot, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Manifest

extension ModelManager {
    static let manifestURL = URL(
        string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/manifest.json"
    )!
}

// MARK: - SigLIP2 Model Lookup

extension ModelManager {

    func findSigLIPModelURL() throws -> URL {

        let fm = FileManager.default
        let root = Self.modelsRoot.appendingPathComponent("SigLIP2")

        guard fm.fileExists(atPath: root.path) else {
            throw NSError(
                domain: "SigLIP2Service",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "SigLIP2 directory not found"
                ]
            )
        }

        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "mlmodelc" ||
               fileURL.pathExtension == "mlpackage" {
                return fileURL
            }
        }

        throw NSError(
            domain: "SigLIP2Service",
            code: -2,
            userInfo: [
                NSLocalizedDescriptionKey: "SigLIP2 model file not found"
            ]
        )
    }
}
