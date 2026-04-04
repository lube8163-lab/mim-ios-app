import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey)
    private var acceptedPolicyAt = ""

    @State private var acceptedPrivacy = false
    @State private var acceptedTerms = false

    let onComplete: () -> Void

    private var canContinue: Bool {
        acceptedPrivacy && acceptedTerms
    }

    var body: some View {
        NavigationStack {
            ZStack {
                onboardingBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        heroSection
                        explainerSection
                        languageSection
                        legalSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 144)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomCTA
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colorScheme == .dark
                        ? Color(red: 0.08, green: 0.10, blue: 0.16)
                        : Color(red: 0.95, green: 0.96, blue: 0.99),
                    colorScheme == .dark
                        ? Color(red: 0.10, green: 0.12, blue: 0.20)
                        : Color(red: 0.98, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.76, green: 0.89, blue: 1.0).opacity(colorScheme == .dark ? 0.16 : 0.24))
                .frame(width: 260, height: 260)
                .blur(radius: 18)
                .offset(x: 130, y: -270)

            Circle()
                .fill(Color(red: 0.82, green: 0.93, blue: 0.85).opacity(colorScheme == .dark ? 0.12 : 0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: -120, y: 320)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Semantic Compression")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.accentColor.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.72), in: Capsule())

            VStack(alignment: .leading, spacing: 10) {
                Text(t(ja: "ようこそ", en: "Welcome", zh: "欢迎"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text(
                    t(
                        ja: "まずは表示言語を選んで、アプリの流れをさっと見てから利用前の同意を済ませましょう。",
                        en: "Start by choosing your language, take a quick look at how the app works, then finish the required agreements.",
                        zh: "先选择显示语言，快速看一眼应用的使用方式，然后完成开始前所需同意。"
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private var explainerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t(ja: "このアプリで起こること", en: "How It Works", zh: "应用如何工作"))
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                explainerCard(
                    icon: "square.stack.3d.up",
                    title: t(ja: "1. 投稿時に意味へ圧縮", en: "1. Compress to semantics", zh: "1. 发帖时压缩为语义"),
                    body: t(
                        ja: "画像そのものではなく、caption / prompt / tags と軽量な画像表現を送ります。",
                        en: "Instead of sending the full image, the app sends caption / prompt / tags and a lightweight image representation.",
                        zh: "应用不会直接发送完整图片，而是发送 caption / prompt / tags 与轻量图像表示。"
                    )
                )

                explainerCard(
                    icon: "cpu",
                    title: t(ja: "2. 端末で backend を選択", en: "2. Choose an on-device backend", zh: "2. 在设备端选择 backend"),
                    body: t(
                        ja: "追加モデルがあればそれを使い、無ければ Apple Vision / Image Playground に自動で切り替えられます。",
                        en: "Installed models are used when available; otherwise the app can switch to Apple Vision / Image Playground automatically.",
                        zh: "有已安装模型时优先使用；没有时会自动切换到 Apple Vision / Image Playground。"
                    )
                )

                explainerCard(
                    icon: "photo.artframe",
                    title: t(ja: "3. 閲覧端末ごとに再構成", en: "3. Reconstruct per viewer device", zh: "3. 按查看设备逐端重建"),
                    body: t(
                        ja: "表示画像は見る人の端末で再生成されるため、backend や投稿モードに応じて結果が少し変わります。",
                        en: "Viewed images are regenerated on the viewer's device, so results can vary slightly by backend and post mode.",
                        zh: "显示图像会在查看者设备端重新生成，因此会因 backend 和发布模式不同而略有差异。"
                    )
                )
            }
        }
    }

    private var languageSection: some View {
        onboardingCard(title: t(ja: "表示言語", en: "Display Language", zh: "显示语言")) {
            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                    languageRow(for: language)

                    if index < AppLanguage.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private var legalSection: some View {
        onboardingCard(title: t(ja: "利用前の確認", en: "Before You Start", zh: "开始前确认")) {
            VStack(spacing: 14) {
                legalItem(
                    icon: "checkmark.shield",
                    title: t(ja: "プライバシーポリシー", en: "Privacy Policy", zh: "隐私政策"),
                    description: t(
                        ja: "データの扱いと保存方法を確認できます。",
                        en: "Review how data is handled and stored.",
                        zh: "查看数据的处理和保存方式。"
                    ),
                    isAccepted: $acceptedPrivacy,
                    openTitle: t(ja: "内容を開く", en: "Open document", zh: "打开内容"),
                    destination: AppPreferences.privacyPolicyURL
                )

                legalItem(
                    icon: "doc.text",
                    title: t(ja: "利用規約", en: "Terms of Service", zh: "使用条款"),
                    description: t(
                        ja: "利用条件と禁止事項を確認できます。",
                        en: "Review the usage terms and restrictions.",
                        zh: "查看使用条件和限制事项。"
                    ),
                    isAccepted: $acceptedTerms,
                    openTitle: t(ja: "内容を開く", en: "Open document", zh: "打开内容"),
                    destination: AppPreferences.termsOfServiceURL
                )
            }
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                completeOnboarding()
            } label: {
                Text(t(ja: "開始する", en: "Get Started", zh: "开始使用"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .foregroundColor(canContinue ? .white : disabledCTAForegroundColor)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        canContinue
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(disabledCTABackgroundStyle)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(canContinue ? Color.white.opacity(0.16) : disabledCTABorderColor, lineWidth: 1)
            )
            .disabled(!canContinue)

            Text(
                t(
                    ja: "同意内容は設定画面からいつでも確認できます。",
                    en: "You can review these agreements anytime from Settings.",
                    zh: "你可以随时在设置中查看这些同意内容。"
                )
            )
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(bottomBarBackground)
    }

    private func onboardingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(10)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04), radius: 18, x: 0, y: 10)
        }
    }

    private func explainerCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(body)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private func languageRow(for language: AppLanguage) -> some View {
        Button {
            selectedLanguage = language.rawValue
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selectedLanguage == language.rawValue ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.05))
                        .frame(width: 34, height: 34)

                    Image(systemName: selectedLanguage == language.rawValue ? "checkmark" : "globe")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(selectedLanguage == language.rawValue ? .accentColor : .secondary)
                }

                Text(language.label)
                    .font(.title3.weight(.medium))
                    .foregroundColor(.primary)

                Spacer()

                if selectedLanguage == language.rawValue {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legalItem(
        icon: String,
        title: String,
        description: String,
        isAccepted: Binding<Bool>,
        openTitle: String,
        destination: URL
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: isAccepted)
                    .labelsHidden()
            }

            HStack {
                Link(openTitle, destination: destination)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(isAccepted.wrappedValue ? t(ja: "同意済み", en: "Accepted", zh: "已同意") : t(ja: "未同意", en: "Required", zh: "需要同意"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isAccepted.wrappedValue ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        (isAccepted.wrappedValue ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )
            }
            .padding(.leading, 40)
        }
        .padding(14)
        .background(legalCardBackgroundColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(.secondarySystemBackground).opacity(0.94)
            : Color.white.opacity(0.84)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.88)
    }

    private var legalCardBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.025)
    }

    private var bottomBarBackground: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color(.systemBackground).opacity(0.92) : Color.white.opacity(0.72))
            .background(.ultraThinMaterial)
    }

    private var disabledCTABackgroundStyle: some ShapeStyle {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.24, green: 0.27, blue: 0.34), Color(red: 0.19, green: 0.22, blue: 0.29)]
                : [Color(red: 0.84, green: 0.87, blue: 0.92), Color(red: 0.78, green: 0.82, blue: 0.88)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var disabledCTAForegroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.58)
            : Color.black.opacity(0.5)
    }

    private var disabledCTABorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.48)
    }

    private func completeOnboarding() {
        acceptedPrivacyVersion = AppPreferences.currentPrivacyVersion
        acceptedTermsVersion = AppPreferences.currentTermsVersion
        acceptedPolicyAt = ISO8601DateFormatter().string(from: Date())
        onComplete()
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }
}
