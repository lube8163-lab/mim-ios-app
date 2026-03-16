//
//  UserManager.swift
//  SemanticCompression-v2
//

import Foundation
import Combine
import Security

struct LocalUser: Codable {
    let id: String
    var displayName: String     // UserDefaults
    var avatarUrl: String       // UserDefaults
    var email: String?
    var deleteToken: String
}

final class UserManager: ObservableObject {

    static let shared = UserManager()
    private static let deleteTokenService = "com.semanticcompression.user"
    private static let deleteTokenAccount = "user_delete_token"

    @Published private(set) var currentUser: LocalUser

    private let defaults = UserDefaults.standard
    private let key_userId = "user_id"
    private let key_displayName = "user_displayName"
    private let key_avatarUrl = "user_avatarUrl"
    private let key_email = "user_email"
    private let key_deleteToken = "user_delete_token"

    private init() {
        let id = defaults.string(forKey: key_userId) ?? ""
        let name = defaults.string(forKey: key_displayName) ?? "Anyone"
        let avatar = defaults.string(forKey: key_avatarUrl)
            ?? "https://example.com/avatar/default.png"
        let email = defaults.string(forKey: key_email)
        let deleteToken = Self.loadDeleteToken(defaults: defaults, legacyKey: key_deleteToken)

        self.currentUser = LocalUser(
            id: id,
            displayName: name,
            avatarUrl: avatar,
            email: email,
            deleteToken: deleteToken
        )
    }

    func saveUser(_ user: LocalUser) {
        if Thread.isMainThread {
            applyUser(user)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyUser(user)
            }
        }
    }
    
    func resetUser() {
        let guestUser = LocalUser(
            id: "",
            displayName: "Anyone",
            avatarUrl: "",
            email: nil,
            deleteToken: ""
        )

        if Thread.isMainThread {
            clearStoredUser()
            currentUser = guestUser
            BlockManager.shared.reloadForCurrentUser()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.clearStoredUser()
                self.currentUser = guestUser
                BlockManager.shared.reloadForCurrentUser()
            }
        }
    }

    private func applyUser(_ user: LocalUser) {
        currentUser = user
        defaults.set(user.id, forKey: key_userId)
        defaults.set(user.displayName, forKey: key_displayName)
        defaults.set(user.avatarUrl, forKey: key_avatarUrl)
        defaults.set(user.email, forKey: key_email)
        Self.saveDeleteToken(user.deleteToken)
        defaults.removeObject(forKey: key_deleteToken)
    }

    private func clearStoredUser() {
        defaults.removeObject(forKey: key_userId)
        defaults.removeObject(forKey: key_displayName)
        defaults.removeObject(forKey: key_avatarUrl)
        defaults.removeObject(forKey: key_email)
        defaults.removeObject(forKey: key_deleteToken)
        Self.clearDeleteToken()
    }

    private static func loadDeleteToken(defaults: UserDefaults, legacyKey: String) -> String {
        if let token = loadDeleteTokenFromKeychain(), !token.isEmpty {
            defaults.removeObject(forKey: legacyKey)
            return token
        }

        let legacyToken = defaults.string(forKey: legacyKey) ?? ""
        if !legacyToken.isEmpty {
            saveDeleteTokenToKeychain(legacyToken)
            defaults.removeObject(forKey: legacyKey)
        }
        return legacyToken
    }

    private static func saveDeleteToken(_ token: String) {
        guard !token.isEmpty else {
            clearDeleteToken()
            return
        }
        saveDeleteTokenToKeychain(token)
    }

    private static func clearDeleteToken() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.deleteTokenService,
            kSecAttrAccount as String: Self.deleteTokenAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    private static func loadDeleteTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.deleteTokenService,
            kSecAttrAccount as String: Self.deleteTokenAccount,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func saveDeleteTokenToKeychain(_ token: String) {
        let data = Data(token.utf8)
        clearDeleteToken()

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.deleteTokenService,
            kSecAttrAccount as String: Self.deleteTokenAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
