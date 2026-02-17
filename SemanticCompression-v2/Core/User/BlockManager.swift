import Foundation
import Combine

final class BlockManager: ObservableObject {
    static let shared = BlockManager()

    @Published private(set) var blockedUserIDs: Set<String> = []

    private let defaults = UserDefaults.standard

    private init() {
        loadFromDefaults()
    }

    func isBlocked(_ userId: String?) -> Bool {
        guard let userId else { return false }
        if userId == UserManager.shared.currentUser.id { return false }
        return blockedUserIDs.contains(userId)
    }

    func refreshFromServerIfPossible() async {
        do {
            let ids = try await BlockService.fetchBlockedUsers()
            blockedUserIDs = Set(ids)
            saveToDefaults()
        } catch {
            #if DEBUG
            print("⚠️ blockedUsers fetch failed:", error)
            #endif
        }
    }

    func block(_ blockedUserId: String) async {
        guard blockedUserId != UserManager.shared.currentUser.id else { return }
        blockedUserIDs.insert(blockedUserId)
        saveToDefaults()
        do {
            try await BlockService.block(blockedUserId: blockedUserId)
        } catch {
            #if DEBUG
            print("⚠️ blockUser failed:", error)
            #endif
        }
    }

    func unblock(_ blockedUserId: String) async {
        blockedUserIDs.remove(blockedUserId)
        saveToDefaults()
        do {
            try await BlockService.unblock(blockedUserId: blockedUserId)
        } catch {
            #if DEBUG
            print("⚠️ unblockUser failed:", error)
            #endif
        }
    }

    func filterBlocked(from posts: [Post]) -> [Post] {
        let currentUserId = UserManager.shared.currentUser.id
        return posts.filter { post in
            if post.userId == currentUserId { return true }
            return !isBlocked(post.userId)
        }
    }

    private func storageKey() -> String {
        "blocked_users_\(UserManager.shared.currentUser.id)"
    }

    func reloadForCurrentUser() {
        blockedUserIDs.removeAll()
        loadFromDefaults()
    }

    private func saveToDefaults() {
        defaults.set(Array(blockedUserIDs), forKey: storageKey())
    }

    private func loadFromDefaults() {
        let list = defaults.stringArray(forKey: storageKey()) ?? []
        blockedUserIDs = Set(list)
    }
}
