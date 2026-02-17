import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isRestoring = true

    private var tokens: AuthTokens?

    private init() {
        if hasPersistedUserIdentity(), let loaded = AuthTokenStore.load() {
            tokens = loaded
            isAuthenticated = true
        } else {
            AuthTokenStore.clear()
            isAuthenticated = false
        }
    }

    func restoreIfNeeded() async {
        defer { isRestoring = false }

        guard hasPersistedUserIdentity(), tokens != nil else {
            tokens = nil
            AuthTokenStore.clear()
            isAuthenticated = false
            return
        }

        do {
            _ = try await validAccessToken()
            isAuthenticated = true
        } catch {
            signOutLocal()
        }
    }

    func startOtp(email: String) async throws {
        try await AuthService.startOtp(email: email)
    }

    func verifyOtp(email: String, otp: String) async throws {
        let deviceName = "iOS"
        let payload = try await AuthService.verifyOtp(email: email, otp: otp, deviceName: deviceName)

        tokens = payload.tokens
        AuthTokenStore.save(payload.tokens)
        isAuthenticated = true

        let current = UserManager.shared.currentUser
        UserManager.shared.saveUser(
            LocalUser(
                id: payload.user.id,
                displayName: payload.user.displayName ?? current.displayName,
                avatarUrl: payload.user.avatarUrl ?? current.avatarUrl,
                email: payload.user.email,
                deleteToken: ""
            )
        )
    }

    func validAccessToken() async throws -> String {
        guard var tokens else { throw AuthError.unauthorized }

        let refreshMargin: TimeInterval = 30
        if tokens.accessTokenExpiresAt.timeIntervalSinceNow <= refreshMargin {
            let refreshed = try await AuthService.refresh(refreshToken: tokens.refreshToken)
            self.tokens = refreshed
            tokens = refreshed
            AuthTokenStore.save(refreshed)
        }

        return tokens.accessToken
    }

    func authorizedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        let token = try await validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func logout(allDevices: Bool = false) async {
        let access = tokens?.accessToken
        let refresh = tokens?.refreshToken
        await AuthService.logout(accessToken: access, refreshToken: refresh, allDevices: allDevices)
        signOutLocal()
    }

    func signOutLocal() {
        tokens = nil
        AuthTokenStore.clear()
        isAuthenticated = false
        UserManager.shared.resetUser()
    }

    private func hasPersistedUserIdentity() -> Bool {
        !UserManager.shared.currentUser.id.isEmpty
    }
}
