//
//  UserManager.swift
//  SemanticCompression-v2
//

import Foundation
import Combine

struct LocalUser: Codable {
    let id: String              // Keychain の UUID
    var displayName: String     // UserDefaults
    var avatarUrl: String       // UserDefaults
    var email: String?
    var deleteToken: String     // ← 追加
}

final class UserManager: ObservableObject {

    static let shared = UserManager()

    @Published private(set) var currentUser: LocalUser

    private let defaults = UserDefaults.standard
    private let key_displayName = "user_displayName"
    private let key_avatarUrl = "user_avatarUrl"
    private let key_email = "user_email"
    private let key_deleteToken = "user_delete_token"

    private init() {
        let id = KeychainUserID.shared.getUserID()
        let name = defaults.string(forKey: key_displayName) ?? "Anyone"
        let avatar = defaults.string(forKey: key_avatarUrl)
            ?? "https://example.com/avatar/default.png"
        let email = defaults.string(forKey: key_email)
        let deleteToken = defaults.string(forKey: key_deleteToken) ?? ""

        self.currentUser = LocalUser(
            id: id,
            displayName: name,
            avatarUrl: avatar,
            email: email,
            deleteToken: deleteToken
        )
    }

    func saveUser(_ user: LocalUser) {
        currentUser = user
        defaults.set(user.displayName, forKey: key_displayName)
        defaults.set(user.avatarUrl, forKey: key_avatarUrl)
        defaults.set(user.email, forKey: key_email)
        defaults.set(user.deleteToken, forKey: key_deleteToken)
    }
    
    func resetUser() {
        defaults.removeObject(forKey: key_displayName)
        defaults.removeObject(forKey: key_avatarUrl)
        defaults.removeObject(forKey: key_email)
        defaults.removeObject(forKey: key_deleteToken)

        // ← ここが今有効になる
        KeychainUserID.shared.deleteUserID()

        let newId = KeychainUserID.shared.getUserID()

        currentUser = LocalUser(
            id: newId,
            displayName: "Anyone",
            avatarUrl: "",
            email: nil,
            deleteToken: ""   // ← ここも空でOK
        )
        BlockManager.shared.reloadForCurrentUser()
    }
}
