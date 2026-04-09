import SwiftUI

struct OTPLoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var otp = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var sent = false
    @State private var message: String?
    @State private var showSentToast = false
    @State private var sentToastText = ""
    let allowsSkip: Bool

    init(allowsSkip: Bool = true) {
        self.allowsSkip = allowsSkip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(l("otp.section.sign_in"))) {
                    TextField(l("otp.email.placeholder"), text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    Button {
                        Task { await sendOtp() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(l("otp.send_code"))
                        }
                    }
                    .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if sent {
                    Section(header: Text(l("otp.section.verification_code"))) {
                        TextField("123456", text: $otp)
                            .keyboardType(.numberPad)

                        Button {
                            Task { await verifyOtp() }
                        } label: {
                            if isVerifying {
                                ProgressView()
                            } else {
                                Text(l("otp.sign_in"))
                            }
                        }
                        .disabled(isVerifying || otp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(l("otp.title"))
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
                    Text(sentToastText)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.78))
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSentToast)
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
