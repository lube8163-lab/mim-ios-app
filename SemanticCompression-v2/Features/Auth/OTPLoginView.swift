import AuthenticationServices
import SwiftUI
import UIKit

struct OTPLoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.preferred.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var otp = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var isSigningInWithApple = false
    @State private var sent = false
    @State private var message: String?
    @State private var showSentToast = false
    @State private var sentToastText = ""
    @State private var appleNonce: String?
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    let allowsSkip: Bool

    init(allowsSkip: Bool = true) {
        self.allowsSkip = allowsSkip
    }

    var body: some View {
        NavigationStack {
            ZStack {
                loginBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        loginHeader
                        authenticationPanel

                        if sent {
                            verificationPanel
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if let message {
                            messageBanner(message)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 96)
                }
            }
            .toolbar {
                if allowsSkip {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(l("otp.later")) {
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showSentToast {
                    toastView
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSentToast)
            .animation(.easeInOut(duration: 0.2), value: sent)
            .animation(.easeInOut(duration: 0.2), value: message)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var loginBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(.systemBackground), Color(.secondarySystemBackground)]
                : [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var loginHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14))
                        .frame(width: 38, height: 38)

                    Image(systemName: "lock.shield")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Semantic Compression")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(l("content.sign_in"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }

            Text(l("content.guest.description"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authenticationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                panelLabel(l("otp.section.apple_id"))
                appleSignInButton
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                panelLabel(l("otp.email.placeholder"))

                TextField(l("otp.email.placeholder"), text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(inputBorder)

                Button {
                    Task { await sendOtp() }
                } label: {
                    buttonContent(title: l("otp.send_code"), isLoading: isSending)
                }
                .buttonStyle(.plain)
                .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)
            }
        }
        .padding(14)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(panelBorder)
    }

    private var appleSignInButton: some View {
        Button {
            startAppleSignIn()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)

                HStack(spacing: 10) {
                    if isSigningInWithApple {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20, weight: .semibold))

                        Text("Sign in with Apple")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSigningInWithApple)
        .opacity(isSigningInWithApple ? 0.78 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("Sign in with Apple")
    }

    private var verificationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelLabel(l("otp.section.verification_code"))

            TextField("123456", text: $otp)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(height: 50)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(inputBorder)

            Button {
                Task { await verifyOtp() }
            } label: {
                buttonContent(title: l("otp.sign_in"), isLoading: isVerifying)
            }
            .buttonStyle(.plain)
            .disabled(isVerifying || otp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(otp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)
        }
        .padding(14)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(panelBorder)
    }

    private func panelLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func buttonContent(title: String, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)

            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(colorScheme == .dark ? 0.14 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 1)
        )
    }

    private var toastView: some View {
        Text(sentToastText)
            .font(.footnote.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(.secondarySystemBackground).opacity(0.82)
            : Color(.systemBackground)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
    }

    private var inputBackground: Color {
        colorScheme == .dark
            ? Color(.tertiarySystemBackground)
            : Color(.secondarySystemGroupedBackground)
    }

    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
    }

    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleIDNonce.random()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleIDNonce.sha256(nonce)
    }

    private func startAppleSignIn() {
        guard !isSigningInWithApple else { return }

        message = nil
        isSigningInWithApple = true

        let request = ASAuthorizationAppleIDProvider().createRequest()
        configureAppleSignIn(request)

        let coordinator = AppleSignInCoordinator { result in
            Task { @MainActor in
                appleSignInCoordinator = nil
                await completeAppleSignIn(result)
            }
        }
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        appleSignInCoordinator = coordinator
        controller.performRequests()
    }

    @MainActor
    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isSigningInWithApple = true
        defer {
            isSigningInWithApple = false
            appleNonce = nil
        }

        do {
            let authorization = try result.get()
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = appleNonce,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                throw AuthError.invalidResponse
            }

            let authorizationCode = credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)
            }

            try await authManager.signInWithApple(
                identityToken: identityToken,
                nonce: nonce,
                fullName: AppleSignInFullName(credential.fullName),
                authorizationCode: authorizationCode
            )
            message = nil
            dismiss()
        } catch {
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                return
            }
            if case let AuthError.server(serverMessage) = error {
                message = l("otp.error.apple_sign_in_server", serverMessage)
            } else {
                message = l("otp.error.apple_sign_in")
            }
        }
    }

    private func sendOtp() async {
        isSending = true
        defer { isSending = false }

        do {
            try await authManager.startOtp(email: email)
            sent = true
            message = nil
            sentToastText = l("otp.toast.code_sent")
            withAnimation(.easeInOut(duration: 0.2)) {
                showSentToast = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSentToast = false
                }
            }
        } catch {
            if case let AuthError.server(serverMessage) = error {
                message = l("otp.error.send_code_server", serverMessage)
            } else {
                message = l("otp.error.send_code")
            }
        }
    }

    private func verifyOtp() async {
        isVerifying = true
        defer { isVerifying = false }

        do {
            try await authManager.verifyOtp(email: email, otp: otp)
            message = nil
            dismiss()
        } catch {
            if case let AuthError.server(serverMessage) = error {
                message = l("otp.error.verify_code_server", serverMessage)
            } else {
                message = l("otp.error.verify_code")
            }
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        completion(.success(authorization))
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}
