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
                Section(header: Text(t(ja: "ログイン", en: "Sign In"))) {
                    TextField(t(ja: "メールアドレス", en: "Email"), text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    Button {
                        Task { await sendOtp() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(t(ja: "認証コードを送信", en: "Send Code"))
                        }
                    }
                    .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if sent {
                    Section(header: Text(t(ja: "認証コード", en: "Verification Code"))) {
                        TextField("123456", text: $otp)
                            .keyboardType(.numberPad)

                        Button {
                            Task { await verifyOtp() }
                        } label: {
                            if isVerifying {
                                ProgressView()
                            } else {
                                Text(t(ja: "ログイン", en: "Sign In"))
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
            .navigationTitle(t(ja: "メール認証", en: "Email OTP"))
            .toolbar {
                if allowsSkip {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t(ja: "あとで", en: "Later")) {
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
            sentToastText = t(
                ja: "認証コードを送信しました。メールをご確認ください。",
                en: "Code sent. Please check your email."
            )
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
                message = t(
                    ja: "認証コード送信に失敗しました: \(serverMessage)",
                    en: "Failed to send code: \(serverMessage)"
                )
            } else {
                message = t(ja: "認証コード送信に失敗しました。", en: "Failed to send code.")
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
                message = t(
                    ja: "コード認証に失敗しました: \(serverMessage)",
                    en: "Failed to verify code: \(serverMessage)"
                )
            } else {
                message = t(ja: "コード認証に失敗しました。", en: "Failed to verify code.")
            }
        }
    }

    private func t(ja: String, en: String) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en)
    }
}
