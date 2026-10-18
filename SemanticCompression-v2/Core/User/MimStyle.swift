import SwiftUI

enum MimStyle {
    static let accent = Color(red: 0.20, green: 0.39, blue: 0.87)
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.063, green: 0.071, blue: 0.078, alpha: 1) : .white })
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.17, green: 0.19, blue: 0.21, alpha: 1)
        : UIColor(red: 0.91, green: 0.93, blue: 0.94, alpha: 1) })
    static let soft = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.13, blue: 0.15, alpha: 1)
        : UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1) })
    static let mediaRadius: CGFloat = 12
}

struct MimPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(enabled ? .white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(enabled ? MimStyle.accent : MimStyle.soft, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    func mimLogoutConfirmation(isPresented: Binding<Bool>, onLogout: @escaping () -> Void) -> some View {
        alert(mt("ログアウトしますか？"), isPresented: isPresented) {
            Button(mt("ログアウト"), role: .destructive) {
                #if DEBUG
                guard !ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { return }
                #endif
                onLogout()
            }
            Button(mt("キャンセル"), role: .cancel) {}
        } message: {
            Text(mt("この端末からログアウトします。投稿は削除されません。再び投稿やいいねをするにはログインが必要です。"))
        }
    }
}
