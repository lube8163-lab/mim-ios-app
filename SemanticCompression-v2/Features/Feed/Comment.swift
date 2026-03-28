import Foundation

struct PostComment: Identifiable, Codable, Hashable {
    let id: String
    let postId: String
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let text: String
    let parentCommentId: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case userId
        case displayName
        case avatarUrl
        case text
        case parentCommentId
        case createdAt
    }

    init(
        id: String,
        postId: String,
        userId: String,
        displayName: String?,
        avatarUrl: String?,
        text: String,
        parentCommentId: String?,
        createdAt: Date
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.text = text
        self.parentCommentId = parentCommentId
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        postId = try c.decode(String.self, forKey: .postId)
        userId = try c.decode(String.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        text = try c.decode(String.self, forKey: .text)
        parentCommentId = try c.decodeIfPresent(String.self, forKey: .parentCommentId)

        createdAt = ServerDate.decodeDate(from: c, forKey: .createdAt)
    }
}

extension PostComment {
    var isByCurrentUser: Bool {
        userId == UserManager.shared.currentUser.id
    }
}
