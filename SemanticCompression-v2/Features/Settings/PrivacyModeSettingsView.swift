import SwiftUI

struct PrivacyModeSettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.selectedPrivacyModeKey)
    private var selectedModeRaw = PrivacyMode.l2.storageValue
    @State private var showL4Warning = false
    @State private var previousModeRawBeforeL4Warning: Int?

    var body: some View {
        List {
            Section {
                Text(l("privacy_mode.description"))
                .font(.footnote)
                .foregroundColor(.secondary)

                if modelManager.resolvedImageGenerationBackend == .stableDiffusion &&
                    modelManager.selectedSDModelID == ModelManager.sd15LCMModelID {
                    Text(l("privacy_mode.lcm_disabled"))
                    .font(.footnote)
                    .foregroundColor(.orange)
                }
            }

            Section(l("privacy_mode.default_section")) {
                ForEach(PrivacyMode.allCases) { mode in
                    Button {
                        guard PrivacyModeAccessPolicy.canUse(mode: mode) else { return }
                        let current = PrivacyMode.fromStorageValue(selectedModeRaw)
                        if current != .l2Prime && mode == .l2Prime {
                            previousModeRawBeforeL4Warning = selectedModeRaw
                            selectedModeRaw = mode.storageValue
                            showL4Warning = true
                        } else {
                            previousModeRawBeforeL4Warning = nil
                            selectedModeRaw = mode.storageValue
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.iconName)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(for: mode))
                                Text(description(for: mode))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if mode.storageValue == selectedModeRaw {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(!PrivacyModeAccessPolicy.canUse(mode: mode))
                    .disabled(
                        modelManager.resolvedImageGenerationBackend == .stableDiffusion &&
                        modelManager.selectedSDModelID == ModelManager.sd15LCMModelID
                    )
                }
            }
        }
        .navigationTitle(l("privacy_mode.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            l("privacy_mode.l4_warning"),
            isPresented: $showL4Warning
        ) {
            Button(l("common.continue"), role: .destructive) {
                previousModeRawBeforeL4Warning = nil
            }
            Button(l("common.cancel"), role: .cancel) {
                if let previousModeRawBeforeL4Warning {
                    selectedModeRaw = previousModeRawBeforeL4Warning
                }
                self.previousModeRawBeforeL4Warning = nil
            }
        }
    }

    private func label(for mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return l("privacy_mode.label.l1")
        case .l2:
            return l("privacy_mode.label.l2")
        case .l3:
            return l("privacy_mode.label.l3")
        case .l2Prime:
            return l("privacy_mode.label.l4")
        }
    }

    private func description(for mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return l("privacy_mode.description.l1")
        case .l2:
            return l("privacy_mode.description.l2")
        case .l3:
            return l("privacy_mode.description.l3")
        case .l2Prime:
            return l("privacy_mode.description.l4")
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
