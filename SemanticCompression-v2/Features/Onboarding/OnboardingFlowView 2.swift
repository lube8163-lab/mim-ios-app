import SwiftUI

struct OnboardingFlowView: View {
    private enum Step {
        case language
        case overview
    }

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
    @State private var step: Step = .language

    let onComplete: () -> Void

    private var canContinue: Bool {
        acceptedPrivacy && acceptedTerms
    }

    var body: some View {
        NavigationStack {
            ZStack {
                onboardingBackground

                if step == .language {
                    languageSelectionPage
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            heroSection
                            explainerSection
                            aiFallbackSection
                            legalSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 144)
                    }
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
            topBrandHeader

            VStack(alignment: .leading, spacing: 10) {
                Text(l("onboarding.welcome"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text(l("onboarding.welcome.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private var explainerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l("onboarding.how_it_works"))
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                explainerCard(
                    icon: "square.stack.3d.up",
                    title: l("onboarding.explainer.compress.title"),
                    body: l("onboarding.explainer.compress.body")
                )

                explainerCard(
                    icon: "cpu",
                    title: l("onboarding.explainer.backend.title"),
                    body: l("onboarding.explainer.backend.body")
                )

                explainerCard(
                    icon: "photo.artframe",
                    title: l("onboarding.explainer.reconstruct.title"),
                    body: l("onboarding.explainer.reconstruct.body")
                )
            }
        }
    }

    private var languageSelectionPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            topBrandHeader

            VStack(alignment: .leading, spacing: 12) {
                Text(l("onboarding.language.title"))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }

            onboardingCard {
                ScrollView(showsIndicators: false) {
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
                .frame(maxHeight: 430)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 144)
    }

    private var topBrandHeader: some View {
        HStack {
            Text("Semantic Compression")
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.accentColor.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.68), in: Capsule())

            Spacer()
        }
        .padding(.top, 2)
    }

    private var aiFallbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l("onboarding.ai_fallback.title"))
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                explainerCard(
                    icon: "eye",
                    title: l("onboarding.ai_fallback.understanding.title"),
                    body: l("onboarding.ai_fallback.understanding.body")
                )

                explainerCard(
                    icon: "wand.and.stars",
                    title: l("onboarding.ai_fallback.generation.title"),
                    body: l("onboarding.ai_fallback.generation.body"),
                    emphasis: l("onboarding.ai_fallback.generation.emphasis")
                )

                explainerCard(
                    icon: "slider.horizontal.3",
                    title: l("onboarding.ai_fallback.settings.title"),
                    body: l("onboarding.ai_fallback.settings.body")
                )
            }
        }
    }

    private var legalSection: some View {
        onboardingCard(title: l("onboarding.before_you_start")) {
            VStack(spacing: 14) {
                legalItem(
                    icon: "checkmark.shield",
                    title: l("onboarding.legal.privacy.title"),
                    description: l("onboarding.legal.privacy.description"),
                    isAccepted: $acceptedPrivacy,
                    openTitle: l("onboarding.legal.open_document"),
                    destination: AppPreferences.privacyPolicyURL
                )

                legalItem(
                    icon: "doc.text",
                    title: l("onboarding.legal.terms.title"),
                    description: l("onboarding.legal.terms.description"),
                    isAccepted: $acceptedTerms,
                    openTitle: l("onboarding.legal.open_document"),
                    destination: AppPreferences.termsOfServiceURL
                )
            }
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 10) {
            Button {
                if step == .language {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .overview
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(step == .language ? l("common.continue") : l("onboarding.get_started"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .foregroundColor(step == .language || canContinue ? .white : disabledCTAForegroundColor)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        step == .language || canContinue
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
                    .stroke(step == .language || canContinue ? Color.white.opacity(0.16) : disabledCTABorderColor, lineWidth: 1)
            )
            .disabled(step == .overview && !canContinue)

            Text(step == .language ? l("onboarding.language.change_later") : l("onboarding.agreements_review"))
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
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04), radius: 18, x: 0, y: 10)
        }
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    private func explainerCard(icon: String, title: String, body: String, emphasis: String? = nil) -> some View {
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

                if let emphasis {
                    Text(emphasis)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.32 : 0.24), lineWidth: 1)
                        )
                        .padding(.top, 4)
                }
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                Spacer()

                if selectedLanguage == language.rawValue {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(minHeight: 84)
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

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}
