import SwiftUI
import PhotosUI

struct NewPostView: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var posts: [Post]
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.selectedPrivacyModeKey)
    private var selectedPrivacyModeRaw = PrivacyMode.l2.storageValue
    @AppStorage(AppPreferences.proModeEnabledKey)
    private var isProModeEnabled = false

    @EnvironmentObject var taggerHolder: TaggerHolder
    @EnvironmentObject var modelManager: ModelManager
    var onSemanticProcessingWillStart: (() -> Void)? = nil
    var onSemanticProcessingDidFinish: (() -> Void)? = nil

    // UI state
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var userText: String = ""
    @State private var selectedMode: PrivacyMode = .l2

    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var extractedTags: [String] = []
    @State private var showSemanticCompletionMessage = false
    @State private var showL2PrimeWarning = false
    @State private var showModeSheet = false
    @State private var hasAcknowledgedCurrentL4Selection = true
    @State private var warningTriggeredFromPostAction = false
    @State private var previousModeBeforeL4Warning: PrivacyMode? = nil
    @State private var lastNonL4Mode: PrivacyMode = .l2
    @State private var postingPhase: PostingPhase?

    private let uploader = PostUploader()
    private let maxPostTextLength = 300
    private let prohibitedKeywords = [
        "kill", "murder", "suicide", "rape", "nude", "porn", "child porn",
        "殺す", "死ね", "自殺", "レイプ", "児童ポルノ", "違法薬物"
    ]

    private var isLCMSelected: Bool {
        modelManager.resolvedImageGenerationBackend == .stableDiffusion &&
        modelManager.selectedSDModelID == ModelManager.sd15LCMModelID
    }

    var body: some View {
        NavigationView {
            ZStack {
                newPostBackground

                VStack(spacing: 0) {

                    // ===== 上：スクロール領域（画像プレビューなど） =====
                    ScrollView {
                        VStack(spacing: 14) {

                            if let img = selectedImage {
                                imagePreview(img)
                            }

                            if selectedImage != nil {
                                imageUnderstandingStatusCard
                            }

                            if isPosting, selectedImage != nil {
                                postingTagStreamSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)
                    }

                    Divider()

                    // ===== 下：常に操作できるComposer（TextEditorはここ） =====
                    composerArea
                }
            }
            .navigationTitle(l("new_post.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button(l("new_post.close")) { dismiss() }
                        .disabled(isPosting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isPosting ? l("new_post.posting") : l("new_post.post")) {
                        requestPost()
                    }
                    .disabled(
                        isPosting ||
                        (selectedImage == nil &&
                         userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showSemanticCompletionMessage {
                Text(
                    l("new_post.semantic_completion")
                )
                .font(.footnote)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.78))
                .clipShape(Capsule())
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .overlay {
            if let postingPhase, isPosting, selectedImage != nil {
                postingProgressOverlay(phase: postingPhase)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .alert(
            l("new_post.l4_warning.title"),
            isPresented: $showL2PrimeWarning
        ) {
            Button(l("new_post.continue"), role: .destructive) {
                hasAcknowledgedCurrentL4Selection = true
                previousModeBeforeL4Warning = nil
                if warningTriggeredFromPostAction {
                    warningTriggeredFromPostAction = false
                    Task { await handlePost() }
                }
            }
            Button(l("common.cancel"), role: .cancel) {
                if let prev = previousModeBeforeL4Warning {
                    selectedMode = prev
                    hasAcknowledgedCurrentL4Selection = true
                } else if selectedMode == .l2Prime {
                    selectedMode = lastNonL4Mode
                    hasAcknowledgedCurrentL4Selection = true
                }
                previousModeBeforeL4Warning = nil
                warningTriggeredFromPostAction = false
            }
        }
    }
}

// MARK: - Composer Area

extension NewPostView {
    private enum PostingPhase {
        case generatingPrompt
        case uploading
    }

    private var postingTagStreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RainbowAILoader()
                Text(postingPhaseTitle(postingPhase ?? .uploading))
                    .font(.subheadline.weight(.semibold))
            }

            Text(l("new_post.whats_being_sent"))
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(extractedTags.enumerated()), id: \.offset) { _, tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }

    private func postingProgressOverlay(phase: PostingPhase) -> some View {
        VStack(spacing: 10) {
            RainbowAILoader()

            Text(postingPhaseTitle(phase))
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(postingPhaseSubtitle(phase))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .padding(28)
    }

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(alignment: .top, spacing: 12) {

                userAvatar

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(UserManager.shared.currentUser.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if selectedImage != nil {
                            Label(l("new_post.image_attached"), systemImage: "photo")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(l("new_post.placeholder"))
                                .foregroundColor(.secondary)
                                .padding(.top, 10)
                                .padding(.leading, 6)
                        }

                        TextEditor(text: $userText)
                            .frame(minHeight: 88, maxHeight: 128)
                            .padding(4)
                            .scrollContentBackground(.hidden)
                            .onChange(of: userText) { newValue in
                                if newValue.count > maxPostTextLength {
                                    userText = String(newValue.prefix(maxPostTextLength))
                                }
                            }
                    }
                }
            }

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(l("new_post.image"), systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                Spacer()

                if selectedImage != nil {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button {
                            guard !isLCMSelected else { return }
                            showModeSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selectedMode.iconName)
                                Text(selectedMode.title(languageCode: selectedLanguage))
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.14))
                            .clipShape(Capsule())
                        }
                        .disabled(isLCMSelected)

                        if isLCMSelected {
                            Text(
                                l("new_post.lcm_note")
                            )
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                if selectedImage != nil {
                    Label(
                        l("new_post.semantic_compression_enabled"),
                        systemImage: "sparkles"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(userText.count)/\(maxPostTextLength)")
                    .font(.caption2)
                    .foregroundColor(userText.count >= maxPostTextLength ? .orange : .secondary)
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onChange(of: selectedItem) { _ in loadImage() }
        .sheet(isPresented: $showModeSheet) {
            modeSelectionSheet
        }
        .onAppear {
            let mode = PrivacyMode.fromStorageValue(selectedPrivacyModeRaw)
            selectedMode = PrivacyModeAccessPolicy.canUse(mode: mode) ? mode : .l2
            lastNonL4Mode = (selectedMode == .l2Prime) ? .l2 : selectedMode
            hasAcknowledgedCurrentL4Selection = (selectedMode != .l2Prime)
        }
        .onChange(of: selectedPrivacyModeRaw) { newValue in
            let mode = PrivacyMode.fromStorageValue(newValue)
            selectedMode = PrivacyModeAccessPolicy.canUse(mode: mode) ? mode : .l2
            if selectedMode != .l2Prime { lastNonL4Mode = selectedMode }
            hasAcknowledgedCurrentL4Selection = (selectedMode != .l2Prime)
        }
    }

    private var modeSelectionSheet: some View {
        NavigationStack {
            List {
                ForEach(PrivacyMode.allCases) { mode in
                    Button {
                        guard PrivacyModeAccessPolicy.canUse(mode: mode) else { return }
                        let switchedToL4 = (selectedMode != .l2Prime && mode == .l2Prime)
                        let previous = selectedMode
                        selectedMode = mode
                        if mode != .l2Prime { lastNonL4Mode = mode }
                        hasAcknowledgedCurrentL4Selection = (mode != .l2Prime)
                        showModeSheet = false
                        if switchedToL4 {
                            previousModeBeforeL4Warning = previous
                            warningTriggeredFromPostAction = false
                            showL2PrimeWarning = true
                        } else {
                            previousModeBeforeL4Warning = nil
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.iconName)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title(languageCode: selectedLanguage))
                                    .font(.body)
                                Text(modeDescription(mode))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(!PrivacyModeAccessPolicy.canUse(mode: mode))
                }
            }
            .navigationTitle(l("new_post.post_mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l("new_post.close")) { showModeSheet = false }
                }
            }
        }
    }

    private func modeDescription(_ mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return l("new_post.mode.l1")
        case .l2:
            return l("new_post.mode.l2")
        case .l3:
            return l("new_post.mode.l3")
        case .l2Prime:
            return l("new_post.mode.l2prime")
        }
    }

    private var userAvatar: some View {
        let name = UserManager.shared.currentUser.displayName
        let initial = String(name.prefix(1)).uppercased()

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            Text(initial)
                .foregroundColor(.white)
                .font(.headline)
        }
    }
}

// MARK: - Image Preview

extension NewPostView {

    private func imagePreview(_ img: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)

            Button {
                selectedItem = nil
                selectedImage = nil
                extractedTags = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                    .padding(18)
            }
            .accessibilityLabel(l("new_post.remove_image"))
        }
    }

    private var imageUnderstandingStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                l("new_post.extracting_semantics"),
                systemImage: "sparkles.rectangle.stack"
            )
            .font(.subheadline.weight(.semibold))

            Text(l("new_post.current_backend", modelManager.resolvedImageUnderstandingBackendTitle))
            .font(.caption)
            .foregroundColor(.secondary)

            if modelManager.resolvedImageUnderstandingBackend == .vision {
                Text(l("new_post.apple_vision_fallback"))
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        )
    }

    private var newPostBackground: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

// MARK: - Logic

extension NewPostView {

    private func requestPost() {
        if selectedImage != nil && selectedMode == .l2Prime && !hasAcknowledgedCurrentL4Selection {
            warningTriggeredFromPostAction = true
            showL2PrimeWarning = true
            return
        }
        Task { await handlePost() }
    }

    func loadImage() {
        Task {
            if let data = try? await selectedItem?.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = ui
                    extractedTags = []
                }
            }
        }
    }

    func handlePost(forceTextOnly: Bool = false) async {

        guard !isPosting else { return }
        let imageForPost = forceTextOnly ? nil : selectedImage
        await MainActor.run {
            isPosting = true
            errorMessage = nil
            extractedTags = []
            showSemanticCompletionMessage = false
            postingPhase = imageForPost != nil ? .generatingPrompt : .uploading
        }
        defer {
            Task { @MainActor in
                isPosting = false
                postingPhase = nil
            }
        }

        let id = UUID().uuidString
        let localUser = UserManager.shared.currentUser

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !PrivacyModeAccessPolicy.canUse(mode: selectedMode) {
            await MainActor.run {
                errorMessage = l("new_post.error.mode_unavailable")
            }
            return
        }
        if containsProhibitedText(trimmed) {
            await MainActor.run {
                errorMessage = l("new_post.error.prohibited_text")
            }
            return
        }

        let modeForPost: PrivacyMode = (imageForPost == nil) ? .l1 : selectedMode
        let payload = imageForPost.flatMap { PostPayload.make(from: $0, mode: modeForPost) }

        if imageForPost != nil && modeForPost != .l1 && payload == nil {
            await MainActor.run {
                errorMessage = l("new_post.error.payload_failed")
            }
            return
        }

        // ① 即時表示用ローカルポスト
        let tempPost = Post(
            id: id,
            userId: localUser.id,
            displayName: localUser.displayName,
            avatarUrl: localUser.avatarUrl,
            caption: nil,
            semanticPrompt: nil,
            regionTags: nil,
            lowResGuide: nil,
            mode: modeForPost.rawValue,
            payload: payload,
            tags: [],
            userText: trimmed.isEmpty ? nil : trimmed,
            hasImage: imageForPost != nil,
            status: .pending,
            createdAt: Date(),
            localImage: imageForPost
        )

        if let imageForPost, isProModeEnabled {
            ImageCacheManager.shared.save(
                imageForPost,
                for: tempPost.id,
                namespace: .originalImages
            )
        }

        await MainActor.run {
            posts.insert(tempPost, at: 0)
        }

        if imageForPost != nil {
            onSemanticProcessingWillStart?()
            defer {
                onSemanticProcessingDidFinish?()
            }
        }

        // ② Semantic Extraction（画像があるときだけ）
        if imageForPost != nil {
            await SemanticExtractionTask.shared.process(
                post: tempPost,
                taggers: taggerHolder
            ) { tags in
                for tag in tags where !extractedTags.contains(tag) {
                    Task { @MainActor in
                        withAnimation(.easeIn(duration: 0.3)) {
                            extractedTags.append(tag)
                        }
                    }
                }
            }
        } else {
            #if DEBUG
            print("ℹ️ Skip semantic extraction (no image)")
            #endif
        }

        // ③ Upload
        do {
            await MainActor.run {
                postingPhase = .uploading
            }
            let uploaded = try await uploader.upload(post: tempPost)

            await MainActor.run {
                tempPost.id = uploaded.id
            }

            if let imageForPost, isProModeEnabled {
                ImageCacheManager.shared.save(
                    imageForPost,
                    for: uploaded.id,
                    namespace: .originalImages
                )
            }

            if tempPost.hasImage {
                do {
                    try await SemanticExtractionTask.shared.syncGeneratedMetadata(
                        post: tempPost,
                        remotePostID: uploaded.id
                    )
                } catch {
                    #if DEBUG
                    print("⚠️ Metadata sync failed:", error)
                    #endif
                }
            }
            if tempPost.hasImage {
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        showSemanticCompletionMessage = true
                    }
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
            await MainActor.run {
                showSemanticCompletionMessage = false
                dismiss()
            }
        } catch {
            #if DEBUG
            print("⚠️ Upload failed:", error)
            #endif
            if imageForPost != nil && isProModeEnabled {
                ImageCacheManager.shared.remove(for: tempPost.id, namespace: .originalImages)
            }
            await MainActor.run {
                posts.removeAll { $0.id == tempPost.id }
                showSemanticCompletionMessage = false
                errorMessage = l("new_post.error.upload_failed")
            }
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }

    private func containsProhibitedText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return prohibitedKeywords.contains { normalized.contains($0.lowercased()) }
    }

    private func postingPhaseTitle(_ phase: PostingPhase) -> String {
        switch phase {
        case .generatingPrompt:
            return l("new_post.phase.generating_prompt")
        case .uploading:
            return l("new_post.phase.uploading")
        }
    }

    private func postingPhaseSubtitle(_ phase: PostingPhase) -> String {
        switch phase {
        case .generatingPrompt:
            return l("new_post.phase.generating_prompt_detail")
        case .uploading:
            return l("new_post.phase.uploading_detail")
        }
    }

}
