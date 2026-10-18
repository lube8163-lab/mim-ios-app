import SwiftUI

struct OnboardingFlowView: View {
    @AppStorage(AppPreferences.selectedLanguageKey) private var language = AppLanguage.preferred.rawValue
    @EnvironmentObject private var modelManager: ModelManager
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey) private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey) private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey) private var acceptedPolicyAt = ""
    @State private var step = 0
    @State private var acceptedPrivacy = false
    @State private var acceptedTerms = false
    @State private var presentedLegalDocument: LegalDocumentKind?
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 29
    let onComplete: () -> Void

    var body: some View {
        let _ = language
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Mim").font(.title2.weight(.semibold))
                    Spacer()
                    if step == 0 {
                        Button(mt("説明をスキップ")) { advance() }
                            .font(.subheadline).frame(minHeight: 44)
                            .accessibilityIdentifier("onboarding-skip")
                    } else {
                        Button { withAnimation { step -= 1 } } label: {
                            Image(systemName: "arrow.left").frame(width: 44, height: 44)
                        }.accessibilityLabel(mt("戻る"))
                    }
                }.padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if step == 0 { introduction }
                        else if step == 1 { sharing }
                        else { models }
                    }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
                        .frame(maxWidth: 520, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                footer
            }
            .background(MimStyle.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedLegalDocument) { document in
                NavigationStack { LegalDocumentDetailView(kind: document, showsCloseButton: true) }
            }
            .onAppear {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--mim-ui-review"), let i = arguments.firstIndex(of: "--mim-ui-review-screen"), arguments.indices.contains(i + 1) {
                    if arguments[i + 1] == "onboarding-sharing" { step = 1 }
                    if arguments[i + 1] == "onboarding-models" { step = 2 }
                }
                #endif
            }
        }.tint(MimStyle.accent)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("同じ投稿から、\nそれぞれの景色。", detail: "写真を言葉で届け、見る人の端末で再生成するSNSです。")
            Image("OnboardingPhoto").resizable().aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: MimStyle.mediaRadius))
                .accessibilityLabel(mt("テーブルの上のりんご。画像の作例。"))
            Text(mt("画像は見る人ごとに変わります。\n元の写真と見た目が変わることがあります。"))
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sharing: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("写真の共有について。", detail: nil)
            fact("iphone", title: "元の写真は、端末の中に。", detail: "投稿に添付した元の写真は、サーバーに送りません。写真は端末内のAIで処理します。")
            fact("text.bubble", title: "写真の説明を共有します。", detail: "写真の説明と再生成に必要な情報は、投稿としてサーバーに保存されます。")
            Text(mt("写真の処理は投稿後に進みます。アプリを閉じた場合は、開き直すと続きから処理します。"))
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                agreement("プライバシーポリシー", isAccepted: $acceptedPrivacy, document: .privacy)
                MimStyle.line.frame(height: 0.5)
                agreement("利用規約", isAccepted: $acceptedTerms, document: .terms)
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("写真を見る準備。", detail: "画像を端末内で再生成するためのモデルをダウンロードします。")
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "photo").font(.title2).frame(width: 32)
                VStack(alignment: .leading, spacing: 8) {
                    Text(mt("画像モデル")).font(.body.weight(.semibold))
                    Text(mt(modelManager.selectedSDModel?.sizeLabel ?? "約4 GB"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(mt(CoreAIFluxAssets.runtimeSupported ? "Wi-Fiでのダウンロードをおすすめします。" : "画像の再現にはiOS 27.0.1以降・RAM 8 GB以上の対応端末が必要です。"))
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.vertical, 12)
            MimStyle.line.frame(height: 0.5)
            fact("text.viewfinder", title: "写真の説明は、投稿するときに。", detail: "説明用モデルは初めて写真を投稿するときに準備します。利用できる端末ではAppleのAIも使えます。")
            Text(mt("モデルがなくても、文章の投稿や写真の説明を読むことから始められます。"))
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule().fill(index == step ? MimStyle.accent : MimStyle.line)
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(mt("はじめに、%d / %d", step + 1, 3))
            Button {
                if step < 2 { advance() }
                else {
                    if !modelManager.sdInstalled && CoreAIFluxAssets.runtimeSupported {
                        modelManager.installSD(modelID: modelManager.selectedSDModelID)
                    }
                    complete()
                }
            } label: {
                Text(mt(step == 0 ? "続ける" : step == 1 ? "同意して進む" : modelManager.sdInstalled || !CoreAIFluxAssets.runtimeSupported ? "Mimをはじめる" : "画像モデルを準備する"))
            }.buttonStyle(MimPrimaryButtonStyle())
                .disabled(step == 1 && !(acceptedPrivacy && acceptedTerms))
                .accessibilityIdentifier("onboarding-continue")
            if step == 2 && CoreAIFluxAssets.runtimeSupported {
                Button(mt("あとで準備する")) { complete() }
                    .font(.subheadline).frame(minHeight: 44)
            }
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
            .frame(maxWidth: 520).frame(maxWidth: .infinity).background(MimStyle.paper)
    }

    private func heading(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mt(title)).font(.system(size: headingSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let detail { Text(mt(detail)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func fact(_ icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 32, height: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(mt(title)).font(.body.weight(.semibold))
                Text(mt(detail)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func agreement(_ title: String, isAccepted: Binding<Bool>, document: LegalDocumentKind) -> some View {
        HStack(spacing: 12) {
            Button { isAccepted.wrappedValue.toggle() } label: {
                Image(systemName: isAccepted.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3).frame(width: 44, height: 52)
            }.buttonStyle(.plain)
                .accessibilityLabel(mt("%@に同意する", mt(title)))
                .accessibilityValue(mt(isAccepted.wrappedValue ? "同意済み" : "未同意"))
                .accessibilityIdentifier(document == .privacy ? "privacy-agreement" : "terms-agreement")
            Button { presentedLegalDocument = document } label: {
                Text(mt(title)).font(.subheadline).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }
    private func advance() { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } }
    private func complete() {
        guard acceptedPrivacy && acceptedTerms else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mim-ui-review") { onComplete(); return }
        #endif
        acceptedPrivacyVersion = AppPreferences.currentPrivacyVersion
        acceptedTermsVersion = AppPreferences.currentTermsVersion
        acceptedPolicyAt = Date().ISO8601Format()
        onComplete()
    }
}
