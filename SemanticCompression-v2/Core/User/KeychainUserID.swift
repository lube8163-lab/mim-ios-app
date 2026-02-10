//
//  KeychainUserID.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/14.
//


//
//  KeychainUserID.swift
//  SemanticCompression-v2
//
//  Created by ChatGPT
//

import Foundation
import Security

final class KeychainUserID {
    
    static let shared = KeychainUserID()
    
    private let account = "SemanticCompressionUserID"
    private let service = "com.semanticcompression.user"
    
    private init() {}
    
    /// 端末ごとの一意の UserID を取得（初回は自動生成）
    func getUserID() -> String {
        if let existing = loadFromKeychain() {
            return existing
        }
        
        let newID = UUID().uuidString
        saveToKeychain(newID)
        return newID
    }
    
    // MARK: - Keychain helpers
    
    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private func saveToKeychain(_ value: String) {
        let data = value.data(using: .utf8)!
        
        // 既存削除
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 新規追加
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func deleteUserID() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}
