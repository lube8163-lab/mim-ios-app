import Foundation

enum AppNotificationType: String, Codable {
    case like
    case comment
    case follow
}

struct AppNotification: Identifiable, Codable {
    let id: String
    let type: AppNotificationType
    let actorUserId: String
    let actorDisplayName: String?
    let actorAvatarUrl: String?
    let postId: String?
    let commentId: String?
    let createdAt: Date
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case actorUserId
        case actorDisplayName
        case actorAvatarUrl
        case postId
        case commentId
        case createdAt
        case isRead
    }

    init(
        id: String,
        type: AppNotificationType,
        actorUserId: String,
        actorDisplayName: String?,
        actorAvatarUrl: String?,
        postId: String?,
        commentId: String?,
        createdAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.type = type
        self.actorUserId = actorUserId
        self.actorDisplayName = actorDisplayName
        self.actorAvatarUrl = actorAvatarUrl
        self.postId = postId
        self.commentId = commentId
        self.createdAt = createdAt
        self.isRead = isRead
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(AppNotificationType.self, forKey: .type)
        actorUserId = try c.decode(String.self, forKey: .actorUserId)
        actorDisplayName = try c.decodeIfPresent(String.self, forKey: .actorDisplayName)
        actorAvatarUrl = try c.decodeIfPresent(String.self, forKey: .actorAvatarUrl)
        postId = try c.decodeIfPresent(String.self, forKey: .postId)
        commentId = try c.decodeIfPresent(String.self, forKey: .commentId)
        createdAt = ServerDate.decodeDate(from: c, forKey: .createdAt)
        if let int = try? c.decode(Int.self, forKey: .isRead) {
            isRead = int != 0
        } else {
            isRead = (try? c.decode(Bool.self, forKey: .isRead)) ?? false
        }
    }
}
