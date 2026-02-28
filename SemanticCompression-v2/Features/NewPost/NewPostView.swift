import SwiftUI
import PhotosUI

struct NewPostView: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var posts: [Post]
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.selectedPrivacyModeKey)
    private var selectedPrivacyModeRaw = PrivacyMode.l2.storageValue

    @EnvironmentObject var taggerHolder: TaggerHolder
    @EnvironmentObject var modelManager: ModelManager

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
    @State private var showSiglipRequiredAlert = false
    @State private var showModeSheet = false
    @State private var hasAcknowledgedCurrentL4Selection = true
    @State private var warningTriggeredFromPostAction = false
    @State private var previousModeBeforeL4Warning: PrivacyMode? = nil
    @State private var lastNonL4Mode: PrivacyMode = .l2

    private let uploader = PostUploader()
    private let maxPostTextLength = 300
    private let prohibitedKeywords = [
        "kill", "murder", "suicide", "rape", "nude", "porn", "child porn",
        "殺す", "死ね", "自殺", "レイプ", "児童ポルノ", "違法薬物"
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // ===== 上：スクロール領域（画像プレビューなど） =====
                ScrollView {
                    VStack(spacing: 12) {

                        if let img = selectedImage {
                            imagePreview(img)
                        }

                        if selectedImage != nil {
                            Text(t(ja: "意味を抽出して再構成します", en: "Extracting semantics and reconstructing"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }

                        if isPosting, selectedImage != nil {
                            postingTagStreamSection
                        }
                    }
                    .padding(.top, 12)
                }

                Divider()

                // ===== 下：常に操作できるComposer（TextEditorはここ） =====
                composerArea
            }
            .navigationTitle(t(ja: "新規投稿", en: "New Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button(t(ja: "閉じる", en: "Close")) { dismiss() }
                        .disabled(isPosting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isPosting ? t(ja: "投稿中…", en: "Posting...") : t(ja: "投稿", en: "Post")) {
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
                    t(
                        ja: "この投稿は、見る人の端末で意味情報から再生成されます。",
                        en: "This post will be reconstructed from semantic data on each viewer's device."
                    )
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
        .alert(
            t(
                ja: "L4 は再現性が高い一方、プライバシーは弱くなります。続行しますか？",
                en: "L4 improves reconstruction but weakens privacy. Continue?"
            ),
            isPresented: $showL2PrimeWarning
        ) {
            Button(t(ja: "続行", en: "Continue"), role: .destructive) {
                hasAcknowledgedCurrentL4Selection = true
                previousModeBeforeL4Warning = nil
                if warningTriggeredFromPostAction {
                    warningTriggeredFromPostAction = false
                    Task { await handlePost() }
                }
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {
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
        .alert(
            t(
                ja: "SigLIP2 が未インストールです",
                en: "SigLIP2 is not installed"
            ),
            isPresented: $showSiglipRequiredAlert
        ) {
            Button(t(ja: "テキストのみ投稿", en: "Post text only")) {
                Task { await handlePost(forceTextOnly: true) }
            }
            Button(t(ja: "キャンセル", en: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                t(
                    ja: "画像の意味抽出ができないため、このままでは画像投稿は反映されません。テキストのみで投稿しますか？",
                    en: "Image semantic extraction is unavailable. Image posts may not appear correctly. Post as text-only?"
                )
            )
        }
    }
}

// MARK: - Composer Area

extension NewPostView {

    private var postingTagStreamSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RainbowAILoader()
                Text(t(ja: "意味情報を送信中…", en: "Sending semantic data..."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(t(ja: "サーバーへ送信中の情報", en: "What's being sent"))
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
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .top, spacing: 12) {

                userAvatar

                ZStack(alignment: .topLeading) {
                    if userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(t(ja: "いまどうしてる？", en: "What's happening?"))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                    }

                    TextEditor(text: $userText)
                        .frame(minHeight: 80, maxHeight: 120)
                        .padding(4)
                        .scrollContentBackground(.hidden)
                        .onChange(of: userText) { newValue in
                            if newValue.count > maxPostTextLength {
                                userText = String(newValue.prefix(maxPostTextLength))
                            }
                        }
                }
            }

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(t(ja: "画像", en: "Image"), systemImage: "photo")
                        .font(.subheadline)
                }

                Spacer()
                
                if selectedImage != nil {
                    Button {
                        showModeSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedMode.iconName)
                            Text(selectedMode.titleEN)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                Spacer()
                Text("\(userText.count)/\(maxPostTextLength)")
                    .font(.caption2)
                    .foregroundColor(userText.count >= maxPostTextLength ? .orange : .secondary)
            }

        }
        .padding(12)
        .background(.ultraThinMaterial)
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
                                Text(t(ja: mode.titleJA, en: mode.titleEN))
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
            .navigationTitle(t(ja: "投稿モード", en: "Post Mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t(ja: "閉じる", en: "Close")) { showModeSheet = false }
                }
            }
        }
    }

    private func modeDescription(_ mode: PrivacyMode) -> String {
        switch mode {
        case .l1:
            return t(ja: "画像情報なし", en: "No image data")
        case .l2:
            return t(ja: "軽量要約", en: "Compact summary")
        case .l3:
            return t(ja: "低周波係数", en: "Low-frequency DCT")
        case .l2Prime:
            return t(ja: "極低解像ピクセル", en: "Extreme low-res pixels")
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
                .frame(height: 220)
                .clipped()
                .cornerRadius(14)
                .padding(.horizontal)

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
            .accessibilityLabel(t(ja: "画像を削除", en: "Remove image"))
        }
    }
}

// MARK: - Logic

extension NewPostView {

    private func requestPost() {
        if selectedImage != nil && !modelManager.siglipInstalled {
            showSiglipRequiredAlert = true
            return
        }
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
        await MainActor.run {
            isPosting = true
            errorMessage = nil
            extractedTags = []
            showSemanticCompletionMessage = false
        }
        defer {
            Task { @MainActor in
                isPosting = false
            }
        }

        let id = UUID().uuidString
        let localUser = UserManager.shared.currentUser

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !PrivacyModeAccessPolicy.canUse(mode: selectedMode) {
            await MainActor.run {
                errorMessage = t(
                    ja: "このモードは現在利用できません。",
                    en: "This mode is currently unavailable."
                )
            }
            return
        }
        if containsProhibitedText(trimmed) {
            await MainActor.run {
                errorMessage = t(
                    ja: "不適切な可能性がある語句を検出しました。内容を修正して再投稿してください。",
                    en: "Potentially objectionable words were detected. Please revise your text."
                )
            }
            return
        }

        let imageForPost = forceTextOnly ? nil : selectedImage
        let modeForPost: PrivacyMode = (imageForPost == nil) ? .l1 : selectedMode
        let payload = imageForPost.flatMap { PostPayload.make(from: $0, mode: modeForPost) }

        if imageForPost != nil && modeForPost != .l1 && payload == nil {
            await MainActor.run {
                errorMessage = t(
                    ja: "中間表現の生成に失敗しました。画像を変更して再試行してください。",
                    en: "Failed to build payload. Please retry with another image."
                )
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

        await MainActor.run {
            posts.insert(tempPost, at: 0)
        }

        // ② Semantic Extraction（画像があるときだけ）
        if imageForPost != nil {
            SemanticExtractionTask.shared.process(
                post: tempPost,
                taggers: taggerHolder
            ) { tags in
                Task { @MainActor in
                    for tag in tags where !extractedTags.contains(tag) {
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
            try await uploader.upload(post: tempPost)
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
            await MainActor.run {
                posts.removeAll { $0.id == tempPost.id }
                showSemanticCompletionMessage = false
                errorMessage = t(ja: "アップロードに失敗しました", en: "Upload failed")
            }
        }
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }

    private func containsProhibitedText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return prohibitedKeywords.contains { normalized.contains($0.lowercased()) }
    }

}
