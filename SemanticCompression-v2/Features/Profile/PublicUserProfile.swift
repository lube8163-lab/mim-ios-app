import Foundation

struct PublicUserProfile: Codable, Identifiable {
    let id: String
    let displayName: String
    let avatarUrl: String
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let postCount: Int
    let isFollowing: Bool
}
