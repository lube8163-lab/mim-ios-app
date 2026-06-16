import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue
    @AppStorage(AppPreferences.acceptedPrivacyVersionKey)
    private var acceptedPrivacyVersion = ""
    @AppStorage(AppPreferences.acceptedTermsVersionKey)
    private var acceptedTermsVersion = ""
    @AppStorage(AppPreferences.acceptedPolicyAtKey)
    private var acceptedPolicyAt = ""

    @State private var acceptedPrivacy = false
    @State private var acceptedTerms = false
    @State private var presentedLegalDocument: LegalDocumentKind?

    let onComplete: () -> Void

    private var canContinue: Bool {
        acceptedPrivacy && acceptedTerms
    }

    var body: some View {
        NavigationStack {
            ZStack {
                onboardingBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        heroSection
                        workflowPreviewSection
                        legalSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 144)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomCTA
            }
            .sheet(item: $presentedLegalDocument) { document in
                NavigationStack {
                    LegalDocumentDetailView(kind: document, showsCloseButton: true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color(.secondarySystemBackground)]
                : [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBrandHeader

            VStack(alignment: .leading, spacing: 10) {
                Text(l("onboarding.welcome"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text(l("onboarding.welcome.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private var topBrandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 40, height: 40)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Semantic Compression")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text("Mim")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var workflowPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l("onboarding.how_it_works"))
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)

            onboardingCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 10) {
                        workflowNode(
                            icon: "photo",
                            title: l("new_post.post"),
                            tint: .blue
                        )

                        workflowArrow

                        workflowNode(
                            icon: "tag",
                            title: semanticPacketLabel,
                            tint: .teal
                        )

                        workflowArrow

                        workflowNode(
                            icon: "wand.and.stars",
                            title: l("content.alert.regenerate.confirm"),
                            tint: .purple
                        )
                    }
                }
                .padding(6)
            }
        }
    }

    private var legalSection: some View {
        onboardingCard(title: l("onboarding.before_you_start")) {
            VStack(spacing: 10) {
                legalItem(
                    icon: "checkmark.shield",
                    title: l("onboarding.legal.privacy.title"),
                    description: l("onboarding.legal.privacy.description"),
                    isAccepted: $acceptedPrivacy,
                    openTitle: l("onboarding.legal.open_document"),
                    document: .privacy
                )

                legalItem(
                    icon: "doc.text",
                    title: l("onboarding.legal.terms.title"),
                    description: l("onboarding.legal.terms.description"),
                    isAccepted: $acceptedTerms,
                    openTitle: l("onboarding.legal.open_document"),
                    document: .terms
                )
            }
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                completeOnboarding()
            } label: {
                Text(l("onboarding.get_started"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(canContinue ? .white : disabledCTAForegroundColor)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        canContinue
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(disabledCTABackgroundStyle)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(canContinue ? Color.white.opacity(0.16) : disabledCTABorderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(!canContinue)

            Text(l("onboarding.agreements_review"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(bottomBarBackground.ignoresSafeArea(edges: .bottom))
    }

    private func onboardingCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(10)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
        }
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(10)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private var workflowArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary.opacity(0.72))
    }

    private func workflowNode(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(height: 64)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(tint)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    private var semanticPacketLabel: String {
        if selectedLanguage.hasPrefix(AppLanguage.japanese.rawValue) {
            return "意味情報"
        }
        if selectedLanguage.hasPrefix(AppLanguage.spanish.rawValue) {
            return "Datos"
        }
        if selectedLanguage.hasPrefix(AppLanguage.portugueseBrazil.rawValue)
            || selectedLanguage.hasPrefix("pt") {
            return "Dados"
        }
        if selectedLanguage.hasPrefix(AppLanguage.korean.rawValue) {
            return "의미 정보"
        }
        if selectedLanguage.hasPrefix(AppLanguage.chineseTraditional.rawValue) {
            return "語意資訊"
        }
        if selectedLanguage.hasPrefix(AppLanguage.chineseSimplified.rawValue) {
            return "语义信息"
        }
        return "Meaning"
    }

    private func legalItem(
        icon: String,
        title: String,
        description _: String,
        isAccepted: Binding<Bool>,
        openTitle: String,
        document: LegalDocumentKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: isAccepted)
                    .labelsHidden()
            }

            HStack {
                Button {
                    presentedLegalDocument = document
                } label: {
                    Label(openTitle, systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text(isAccepted.wrappedValue ? l("onboarding.legal.accepted") : l("onboarding.legal.required"))
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
        .padding(12)
        .background(legalCardBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(.secondarySystemBackground).opacity(0.86)
            : Color(.systemBackground)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var legalCardBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.025)
    }

    private var bottomBarBackground: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color(.systemBackground).opacity(0.92) : Color(.systemBackground).opacity(0.78))
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

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
