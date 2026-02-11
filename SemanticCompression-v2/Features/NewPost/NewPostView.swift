import SwiftUI
import PhotosUI

struct NewPostView: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var posts: [Post]
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue

    @EnvironmentObject var taggerHolder: TaggerHolder
    @EnvironmentObject var modelManager: ModelManager

    // UI state
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var userText: String = ""

    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showEmailRequiredAlert = false

    private let uploader = PostUploader()
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
                        Task { await handlePost() }
                    }
                    .disabled(
                        isPosting ||
                        (selectedImage == nil &&
                         userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
            .alert(
                t(ja: "メール登録が必要です", en: "Email registration required"),
                isPresented: $showEmailRequiredAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(t(
                    ja: "投稿するにはプロフィール画面でメールアドレスを登録してください。",
                    en: "Please register an email address in your profile before posting."
                ))
            }
        }
    }
}

// MARK: - Composer Area

extension NewPostView {

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
                }
            }

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(t(ja: "画像", en: "Image"), systemImage: "photo")
                        .font(.subheadline)
                }

                Spacer()
            }

            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if !isEmailRegistered {
                Text(t(
                    ja: "投稿にはメールアドレス登録が必要です（プロフィール画面で設定）。",
                    en: "Email registration is required to post (set it in Profile)."
                ))
                .foregroundColor(.orange)
                .font(.caption)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .onChange(of: selectedItem) { _ in loadImage() }
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

    func loadImage() {
        Task {
            if let data = try? await selectedItem?.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = ui
                }
            }
        }
    }

    func handlePost() async {

        guard !isPosting else { return }
        await MainActor.run {
            isPosting = true
            errorMessage = nil
        }
        defer {
            Task { @MainActor in
                isPosting = false
            }
        }

        let id = UUID().uuidString
        let localUser = UserManager.shared.currentUser

        guard isEmailRegistered else {
            await MainActor.run {
                showEmailRequiredAlert = true
            }
            return
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsProhibitedText(trimmed) {
            await MainActor.run {
                errorMessage = t(
                    ja: "不適切な可能性がある語句を検出しました。内容を修正して再投稿してください。",
                    en: "Potentially objectionable words were detected. Please revise your text."
                )
            }
            return
        }

        let lowResGuide = selectedImage.flatMap { LowResGuide.encode(from: $0, size: 64) }

        // ① 即時表示用ローカルポスト
        let tempPost = Post(
            id: id,
            userId: localUser.id,
            displayName: localUser.displayName,
            avatarUrl: localUser.avatarUrl,
            caption: nil,
            semanticPrompt: nil,
            regionTags: nil,
            lowResGuide: lowResGuide,
            userText: trimmed.isEmpty ? nil : trimmed,
            hasImage: selectedImage != nil,
            status: .pending,
            createdAt: Date(),
            localImage: selectedImage
        )

        await MainActor.run {
            posts.insert(tempPost, at: 0)
        }

        // ② Semantic Extraction（画像があるときだけ）
        if selectedImage != nil {
            SemanticExtractionTask.shared.process(
                post: tempPost,
                taggers: taggerHolder
            )
        } else {
            #if DEBUG
            print("ℹ️ Skip semantic extraction (no image)")
            #endif
        }

        // ③ Upload
        do {
            try await uploader.upload(post: tempPost)
            await MainActor.run {
                dismiss()
            }
        } catch {
            #if DEBUG
            print("⚠️ Upload failed:", error)
            #endif
            await MainActor.run {
                posts.removeAll { $0.id == tempPost.id }
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

    private var isEmailRegistered: Bool {
        guard let email = UserManager.shared.currentUser.email?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return false
        }
        return email.contains("@") && email.contains(".")
    }
}
