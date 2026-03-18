import Combine
import Foundation

@MainActor
final class ModelManager: ObservableObject {

    struct InstallErrorContext: Identifiable {
        enum Reason {
            case integrityCheckFailed
            case generic(String)
        }

        let id = UUID()
        let modelTitle: String
        let reason: Reason
    }

    static let shared = ModelManager()
    private var cancellables = Set<AnyCancellable>()

    private var siglipInstaller: ModelInstaller?
    private var qwenInstaller: ModelInstaller?
    private var sdInstaller: ModelInstaller?
    private var activeUnderstandingInstallModelID: String?
    private var activeSDInstallModelID: String?

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
        let sizeLabelJA: String
        let sizeLabelEN: String
        let installPath: String
        let downloadURL: URL
        let sha256: String?
    }

    struct ImageUnderstandingModelConfig: Identifiable, Hashable {
        let id: String
        let title: String
        let sizeLabelJA: String
        let sizeLabelEN: String
        let installPath: String
        let downloadURL: URL
        let sha256: String?
    }

    static let sd15ModelID = "sd15"
    static let sd15LCMModelID = "sd15_lcm"
    static let siglipModelID = ImageUnderstandingModel.siglip2.rawValue
    static let qwenVLModelID = ImageUnderstandingModel.qwen35vl.rawValue
    static let qwenVLInstallPath = "Qwen3_5_VL_0_8B"
    static let qwenMainModelFile = "Qwen3.5-0.8B-Q4_K_M.gguf"
    static let qwenMMProjFile = "mmproj-F16.gguf"
    static let siglipRequiredFiles = [
        "caption_10k.json",
        "caption_10k_embs.npy",
        "styles.json",
        "styles_embs.npy",
        "tag_embs_siglip2_base.npy",
        "tag_labels_siglip2_base.json"
    ]

    static let supportedSDModels: [SDModelConfig] = [
        SDModelConfig(
            id: sd15ModelID,
            title: "Stable Diffusion 1.5",
            sizeLabelJA: "約2 GB（Wi-Fi 推奨）",
            sizeLabelEN: "About 2 GB (Wi-Fi recommended)",
            installPath: "StableDiffusion/sd15",
            downloadURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sd15/sd15_coreml_v2.zip"
            )!,
            sha256: "37e4f91b81ac501a9ef7f30ccbc216367de4f5a14a963441fc6ee8abce16e7ed"
        ),
        SDModelConfig(
            id: sd15LCMModelID,
            title: "Stable Diffusion 1.5 (LCM)",
            sizeLabelJA: "約2 GB（Wi-Fi 推奨）",
            sizeLabelEN: "About 2 GB (Wi-Fi recommended)",
            installPath: "StableDiffusion/sd15_lcm",
            downloadURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/SD/sd15/sd15_lcm_coreml_v1_mlmodelc.zip"
            )!,
            sha256: "a45129822a1b199bb639ae1d822a05044f28d7aa911e87bba28879d86a0e49e7"
        )
    ]

    static let supportedImageUnderstandingModels: [ImageUnderstandingModelConfig] = [
        ImageUnderstandingModelConfig(
            id: siglipModelID,
            title: "SigLIP2 Vision Encoder",
            sizeLabelJA: "199 MB",
            sizeLabelEN: "199 MB",
            installPath: "SigLIP2",
            downloadURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/siglip2/siglip2-vision-v2.zip"
            )!,
            sha256: "b39bffde52c58646de7d8c7f117ec37441e59b09f6005073027259c8fbabd8b4"
        ),
        ImageUnderstandingModelConfig(
            id: qwenVLModelID,
            title: "Qwen3.5-VL-0.8B",
            sizeLabelJA: "703 MB",
            sizeLabelEN: "703 MB",
            installPath: qwenVLInstallPath,
            downloadURL: URL(
                string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/qwen/qwen3_5_vl_0_8b_gguf.zip"
            )!,
            sha256: "c06035552b3cd5322ae0dffb851cc283a04f15f8fad9aeeba13c240cd7a67208"
        )
    ]

    @Published var siglipInstalled = false
    @Published var qwenInstalled = false
    @Published var sdInstalled = false
    @Published var selectedImageUnderstandingModelID: String
    @Published var selectedSDModelID: String

    @Published var siglipInstalling = false
    @Published var qwenInstalling = false
    @Published var sdInstalling = false

    @Published var siglipProgress: Double = 0
    @Published var qwenProgress: Double = 0
    @Published var sdProgress: Double = 0

    @Published var siglipDownloadedBytes: Int64 = 0
    @Published var siglipTotalBytes: Int64 = 0
    @Published var qwenDownloadedBytes: Int64 = 0
    @Published var qwenTotalBytes: Int64 = 0
    @Published var sdDownloadedBytes: Int64 = 0
    @Published var sdTotalBytes: Int64 = 0
    @Published var installError: InstallErrorContext?

    var imageUnderstandingModels: [ImageUnderstandingModelConfig] {
        Self.supportedImageUnderstandingModels
    }

    var sdModels: [SDModelConfig] {
        Self.supportedSDModels
    }

    var selectedImageUnderstandingModel: ImageUnderstandingModelConfig {
        Self.supportedImageUnderstandingModels.first(where: { $0.id == selectedImageUnderstandingModelID })
            ?? Self.supportedImageUnderstandingModels[0]
    }

    var selectedSDModel: SDModelConfig {
        Self.supportedSDModels.first(where: { $0.id == selectedSDModelID })
            ?? Self.supportedSDModels[0]
    }

    var hasAnySDInstalled: Bool {
        Self.supportedSDModels.contains { isInstalled(path: $0.installPath) }
    }

    var isModelInstalled: Bool {
        (siglipInstalled || qwenInstalled) && sdInstalled
    }

    static var modelsRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("Models")
    }

    init() {
        selectedImageUnderstandingModelID = UserDefaults.standard.string(
            forKey: AppPreferences.selectedImageUnderstandingModelKey
        ) ?? Self.siglipModelID
        selectedSDModelID = UserDefaults.standard.string(
            forKey: AppPreferences.selectedSDModelKey
        ) ?? Self.supportedSDModels[0].id
        normalizeSelectedImageUnderstandingModelID()
        normalizeSelectedSDModelID()
        reloadState()
    }

    private func isInstalled(path: String) -> Bool {
        let marker = Self.modelsRoot
            .appendingPathComponent(path)
            .appendingPathComponent(".installed")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    private func hasCompleteSigLIPInstallation() -> Bool {
        let root = Self.modelsRoot.appendingPathComponent("SigLIP2")
        guard isInstalled(path: "SigLIP2") else { return false }
        guard (try? findSigLIPModelURL()) != nil else { return false }

        return Self.siglipRequiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(fileName).path
            )
        }
    }

    func reloadState() {
        siglipInstalled = hasCompleteSigLIPInstallation()
        qwenInstalled = isInstalled(path: Self.qwenVLInstallPath)
        normalizeSelectedImageUnderstandingModelID()
        autoSelectInstalledImageUnderstandingModelIfNeeded()
        normalizeSelectedSDModelID()
        autoSelectInstalledSDModelIfNeeded()
        sdInstalled = isInstalled(path: selectedSDModel.installPath)
    }

    func installSigLIP() {
        installImageUnderstandingModel(id: Self.siglipModelID)
    }

    func installQwenVL() {
        installImageUnderstandingModel(id: Self.qwenVLModelID)
    }

    private func installImageUnderstandingModel(id: String) {
        guard !siglipInstalling && !qwenInstalling else { return }
        guard let model = Self.supportedImageUnderstandingModels.first(where: { $0.id == id }) else {
            return
        }
        installError = nil

        // Old SigLIP installs may have only the model payload and .installed marker.
        // Remove incomplete directories so the installer does a full redownload.
        if model.id == Self.siglipModelID && !hasCompleteSigLIPInstallation() {
            let dir = Self.modelsRoot.appendingPathComponent(model.installPath)
            try? FileManager.default.removeItem(at: dir)
        }

        activeUnderstandingInstallModelID = model.id

        switch model.id {
        case Self.siglipModelID:
            siglipInstalling = true
            siglipProgress = 0.01
            siglipDownloadedBytes = 0
            siglipTotalBytes = 0
        case Self.qwenVLModelID:
            qwenInstalling = true
            qwenProgress = 0.01
            qwenDownloadedBytes = 0
            qwenTotalBytes = 0
        default:
            break
        }

        let installer = ModelInstaller(
            modelURL: model.downloadURL,
            modelName: model.installPath,
            expectedSHA256: model.sha256
        )

        if model.id == Self.siglipModelID {
            siglipInstaller = installer
        } else if model.id == Self.qwenVLModelID {
            qwenInstaller = installer
        }

        installer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                if model.id == Self.siglipModelID {
                    self.siglipProgress = max(value, 0.01)
                } else if model.id == Self.qwenVLModelID {
                    self.qwenProgress = max(value, 0.01)
                }
            }
            .store(in: &cancellables)

        installer.$downloadedBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                if model.id == Self.siglipModelID {
                    self.siglipDownloadedBytes = value
                } else if model.id == Self.qwenVLModelID {
                    self.qwenDownloadedBytes = value
                }
            }
            .store(in: &cancellables)

        installer.$totalBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                if model.id == Self.siglipModelID {
                    self.siglipTotalBytes = value
                } else if model.id == Self.qwenVLModelID {
                    self.qwenTotalBytes = value
                }
            }
            .store(in: &cancellables)

        installer.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }

                switch status {
                case .completed:
                    if model.id == Self.siglipModelID {
                        self.siglipInstalling = false
                        self.siglipProgress = 1.0
                    } else if model.id == Self.qwenVLModelID {
                        self.qwenInstalling = false
                        self.qwenProgress = 1.0
                    }
                    self.activeUnderstandingInstallModelID = nil
                    self.reloadState()

                case .failed(let message):
                    if model.id == Self.siglipModelID {
                        self.siglipInstalling = false
                    } else if model.id == Self.qwenVLModelID {
                        self.qwenInstalling = false
                    }
                    self.activeUnderstandingInstallModelID = nil
                    self.installError = InstallErrorContext(
                        modelTitle: model.title,
                        reason: self.installErrorReason(from: message)
                    )

                case .cancelled:
                    if model.id == Self.siglipModelID {
                        self.siglipInstalling = false
                    } else if model.id == Self.qwenVLModelID {
                        self.qwenInstalling = false
                    }
                    self.activeUnderstandingInstallModelID = nil

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
        installError = nil

        sdInstalling = true
        sdProgress = 0.01
        sdDownloadedBytes = 0
        sdTotalBytes = 0
        activeSDInstallModelID = model.id

        let installer = ModelInstaller(
            modelURL: model.downloadURL,
            modelName: model.installPath,
            expectedSHA256: model.sha256
        )
        sdInstaller = installer

        installer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sdProgress = max(value, 0.01)
            }
            .store(in: &cancellables)

        installer.$downloadedBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sdDownloadedBytes = value
            }
            .store(in: &cancellables)

        installer.$totalBytes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sdTotalBytes = value
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

                case .failed(let message):
                    self.sdInstalling = false
                    self.activeSDInstallModelID = nil
                    self.installError = InstallErrorContext(
                        modelTitle: model.title,
                        reason: self.installErrorReason(from: message)
                    )

                case .cancelled:
                    self.sdInstalling = false
                    self.activeSDInstallModelID = nil

                default:
                    break
                }
            }
            .store(in: &cancellables)

        installer.start()
    }

    func selectImageUnderstandingModel(id: String) {
        guard Self.supportedImageUnderstandingModels.contains(where: { $0.id == id }) else { return }
        guard isImageUnderstandingModelInstalled(id) else { return }
        selectedImageUnderstandingModelID = id
        UserDefaults.standard.set(id, forKey: AppPreferences.selectedImageUnderstandingModelKey)
        reloadState()
    }

    func selectSDModel(id: String) {
        guard Self.supportedSDModels.contains(where: { $0.id == id }) else { return }
        selectedSDModelID = id
        UserDefaults.standard.set(id, forKey: AppPreferences.selectedSDModelKey)
        reloadState()
    }

    func isImageUnderstandingModelInstalled(_ modelID: String) -> Bool {
        if modelID == Self.siglipModelID {
            return hasCompleteSigLIPInstallation()
        }
        guard let model = Self.supportedImageUnderstandingModels.first(where: { $0.id == modelID }) else {
            return false
        }
        return isInstalled(path: model.installPath)
    }

    func isImageUnderstandingModelInstalling(_ modelID: String) -> Bool {
        activeUnderstandingInstallModelID == modelID && (siglipInstalling || qwenInstalling)
    }

    func isSDModelInstalled(_ modelID: String) -> Bool {
        guard let model = Self.supportedSDModels.first(where: { $0.id == modelID }) else {
            return false
        }
        return isInstalled(path: model.installPath)
    }

    func clearInstallError() {
        installError = nil
    }

    private func installErrorReason(from message: String) -> InstallErrorContext.Reason {
        let normalized = message.lowercased()
        if normalized.contains("verification failed") || normalized.contains("sha-256") {
            return .integrityCheckFailed
        }
        return .generic(message)
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

    func deleteQwenVLModel() {
        guard !qwenInstalling else { return }
        let dir = Self.modelsRoot.appendingPathComponent(Self.qwenVLInstallPath)
        try? FileManager.default.removeItem(at: dir)
        reloadState()
    }

    var selectedSDModelDirectory: URL {
        Self.modelsRoot.appendingPathComponent(selectedSDModel.installPath)
    }

    func deleteAllModels() {
        try? FileManager.default.removeItem(at: Self.modelsRoot)
        reloadState()
    }

    private func normalizeSelectedImageUnderstandingModelID() {
        if !Self.supportedImageUnderstandingModels.contains(where: { $0.id == selectedImageUnderstandingModelID }) {
            selectedImageUnderstandingModelID = Self.siglipModelID
            UserDefaults.standard.set(
                selectedImageUnderstandingModelID,
                forKey: AppPreferences.selectedImageUnderstandingModelKey
            )
        }
    }

    private func normalizeSelectedSDModelID() {
        if !Self.supportedSDModels.contains(where: { $0.id == selectedSDModelID }) {
            selectedSDModelID = Self.supportedSDModels[0].id
            UserDefaults.standard.set(selectedSDModelID, forKey: AppPreferences.selectedSDModelKey)
        }
    }

    private func autoSelectInstalledImageUnderstandingModelIfNeeded() {
        if isImageUnderstandingModelInstalled(selectedImageUnderstandingModelID) {
            return
        }

        guard let installed = Self.supportedImageUnderstandingModels.first(where: {
            isImageUnderstandingModelInstalled($0.id)
        }) else {
            return
        }

        selectedImageUnderstandingModelID = installed.id
        UserDefaults.standard.set(
            selectedImageUnderstandingModelID,
            forKey: AppPreferences.selectedImageUnderstandingModelKey
        )
    }

    private func autoSelectInstalledSDModelIfNeeded() {
        if isInstalled(path: selectedSDModel.installPath) {
            return
        }

        guard let installed = Self.supportedSDModels.first(where: {
            isInstalled(path: $0.installPath)
        }) else {
            return
        }

        selectedSDModelID = installed.id
        UserDefaults.standard.set(selectedSDModelID, forKey: AppPreferences.selectedSDModelKey)
    }
}

extension ModelManager {
    static let manifestURL = URL(
        string: "https://pub-41a85dcbeaae42d58c317781ea160d68.r2.dev/manifest.json"
    )!
}

extension ModelManager {

    var siglipResourceDirectory: URL? {
        let root = Self.modelsRoot.appendingPathComponent("SigLIP2")
        return hasCompleteSigLIPInstallation() ? root : nil
    }

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

    struct QwenVLModelFiles {
        let modelURL: URL
        let mmprojURL: URL
    }

    func findQwenVLModelFiles() throws -> QwenVLModelFiles {
        let fm = FileManager.default
        let root = Self.modelsRoot.appendingPathComponent(Self.qwenVLInstallPath)
        guard fm.fileExists(atPath: root.path) else {
            throw NSError(
                domain: "QwenVisionLanguageService",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Qwen model directory not found"
                ]
            )
        }

        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )

        var modelURL: URL?
        var mmprojURL: URL?

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == Self.qwenMainModelFile {
                modelURL = fileURL
            } else if fileURL.lastPathComponent == Self.qwenMMProjFile {
                mmprojURL = fileURL
            }
        }

        guard let modelURL else {
            throw NSError(
                domain: "QwenVisionLanguageService",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Qwen main model file not found"
                ]
            )
        }

        guard let mmprojURL else {
            throw NSError(
                domain: "QwenVisionLanguageService",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Qwen mmproj file not found"
                ]
            )
        }

        return QwenVLModelFiles(
            modelURL: modelURL,
            mmprojURL: mmprojURL
        )
    }
}
