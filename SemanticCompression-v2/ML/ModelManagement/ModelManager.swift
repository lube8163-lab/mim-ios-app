import Foundation
import Combine

@MainActor
final class ModelManager: ObservableObject {

    static let shared = ModelManager()
    private var cancellables = Set<AnyCancellable>()

    private var siglipInstaller: ModelInstaller?
    private var sdInstaller: ModelInstaller?
    private var activeSDInstallModelID: String?

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

    struct SDModelConfig: Identifiable, Hashable {
        let id: String
        let title: String
        let sizeLabel: String
        let installPath: String
        let downloadURL: URL
    }

    static let supportedSDModels: [SDModelConfig] = [
        SDModelConfig(
            id: "sd15_coreml_v2",
            title: "Stable Diffusion 1.5",
            sizeLabel: "約2 GB（Wi-Fi 推奨）",
            installPath: "StableDiffusion/sd15",
            downloadURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sd15/sd15_coreml_v2.zip"
            )!
        )
    ]

    // MARK: - Published

    @Published var siglipInstalled = false
    @Published var sdInstalled = false
    @Published var selectedSDModelID: String

    @Published var siglipInstalling = false
    @Published var sdInstalling = false

    @Published var siglipProgress: Double = 0
    @Published var sdProgress: Double = 0

    @Published var siglipDownloadedBytes: Int64 = 0
    @Published var siglipTotalBytes: Int64 = 0

    @Published var sdDownloadedBytes: Int64 = 0
    @Published var sdTotalBytes: Int64 = 0

    var sdModels: [SDModelConfig] {
        Self.supportedSDModels
    }

    var selectedSDModel: SDModelConfig {
        Self.supportedSDModels.first(where: { $0.id == selectedSDModelID })
            ?? Self.supportedSDModels[0]
    }

    var hasAnySDInstalled: Bool {
        Self.supportedSDModels.contains { isInstalled(path: $0.installPath) }
    }

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
        selectedSDModelID = UserDefaults.standard.string(
            forKey: AppPreferences.selectedSDModelKey
        ) ?? Self.supportedSDModels[0].id
        normalizeSelectedSDModelID()
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
        normalizeSelectedSDModelID()
        sdInstalled = isInstalled(path: selectedSDModel.installPath)
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
        installSD(modelID: selectedSDModelID)
    }

    func installSD(modelID: String) {

        guard !sdInstalling else { return }
        guard let model = Self.supportedSDModels.first(where: { $0.id == modelID }) else {
            return
        }

        sdInstalling = true
        sdProgress = 0.01
        sdDownloadedBytes = 0
        sdTotalBytes = 0
        activeSDInstallModelID = model.id

        let installer = ModelInstaller(
            modelURL: model.downloadURL,
            modelName: model.installPath
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
                    self.activeSDInstallModelID = nil
                    self.reloadState()

                case .failed, .cancelled:
                    self.sdInstalling = false
                    self.activeSDInstallModelID = nil

                default:
                    break
                }
            }
            .store(in: &cancellables)

        installer.start()
    }

    func selectSDModel(id: String) {
        guard Self.supportedSDModels.contains(where: { $0.id == id }) else { return }
        selectedSDModelID = id
        UserDefaults.standard.set(id, forKey: AppPreferences.selectedSDModelKey)
        reloadState()
    }

    func isSDModelInstalled(_ modelID: String) -> Bool {
        guard let model = Self.supportedSDModels.first(where: { $0.id == modelID }) else {
            return false
        }
        return isInstalled(path: model.installPath)
    }

    func isSDModelInstalling(_ modelID: String) -> Bool {
        sdInstalling && activeSDInstallModelID == modelID
    }

    func deleteSDModel(_ modelID: String) {
        guard let model = Self.supportedSDModels.first(where: { $0.id == modelID }) else {
            return
        }
        guard !isSDModelInstalling(modelID) else { return }

        let dir = Self.modelsRoot.appendingPathComponent(model.installPath)
        try? FileManager.default.removeItem(at: dir)

        if selectedSDModelID == modelID {
            if let installed = Self.supportedSDModels.first(where: {
                isInstalled(path: $0.installPath)
            }) {
                selectedSDModelID = installed.id
            } else {
                selectedSDModelID = Self.supportedSDModels[0].id
            }
            UserDefaults.standard.set(selectedSDModelID, forKey: AppPreferences.selectedSDModelKey)
        }

        reloadState()
    }

    func deleteSigLIPModel() {
        guard !siglipInstalling else { return }
        let dir = Self.modelsRoot.appendingPathComponent("SigLIP2")
        try? FileManager.default.removeItem(at: dir)
        reloadState()
    }

    var selectedSDModelDirectory: URL {
        Self.modelsRoot.appendingPathComponent(selectedSDModel.installPath)
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

    private func normalizeSelectedSDModelID() {
        if !Self.supportedSDModels.contains(where: { $0.id == selectedSDModelID }) {
            selectedSDModelID = Self.supportedSDModels[0].id
            UserDefaults.standard.set(selectedSDModelID, forKey: AppPreferences.selectedSDModelKey)
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
