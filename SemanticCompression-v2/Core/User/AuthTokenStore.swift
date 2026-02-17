import Foundation
import Security

struct AuthTokens {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
}

enum AuthTokenStore {
    private static let service = "com.semanticcompression.auth"
    private static let accountAccess = "access_token"
    private static let accountRefresh = "refresh_token"
    private static let accessExpKey = "auth_access_exp"

    private static let defaults = UserDefaults.standard

    static func load() -> AuthTokens? {
        guard
            let access = loadKeychain(account: accountAccess),
            let refresh = loadKeychain(account: accountRefresh)
        else {
            return nil
        }

        let exp = defaults.object(forKey: accessExpKey) as? Date ?? .distantPast
        return AuthTokens(accessToken: access, refreshToken: refresh, accessTokenExpiresAt: exp)
    }

    static func save(_ tokens: AuthTokens) {
        saveKeychain(value: tokens.accessToken, account: accountAccess)
        saveKeychain(value: tokens.refreshToken, account: accountRefresh)
        defaults.set(tokens.accessTokenExpiresAt, forKey: accessExpKey)
    }

    static func clear() {
        deleteKeychain(account: accountAccess)
        deleteKeychain(account: accountRefresh)
        defaults.removeObject(forKey: accessExpKey)
    }

    private static func loadKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard
            status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    private static func saveKeychain(value: String, account: String) {
        let data = Data(value.utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteKeychain(account: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}
