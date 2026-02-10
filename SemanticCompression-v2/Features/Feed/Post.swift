//
//  Post.swift
//  SemanticCompression-v2
//

import Foundation
import UIKit
import Combine

// MARK: - Status
enum PostStatus: String, Codable {
    case normal, pending, processing, completed, failed
}

// MARK: - Region tag
struct RegionTag: Codable {
    let region: String
    let tags: [String]
}

// MARK: - Main Post model
final class Post: Identifiable, ObservableObject, Codable {

    let id: String

    // 投稿者
    let userId: String?
    let displayName: String?
    let avatarUrl: String?

    // Semantic
    @Published var caption: String?
    @Published var semanticPrompt: String?
    @Published var regionTags: [RegionTag]?

    // User content
    let userText: String?
    @Published var hasImage: Bool

    let createdAt: Date
    @Published var status: PostStatus

    // Social
    @Published var likeCount: Int?
    @Published var isLikedByCurrentUser: Bool?

    // Local image
    @Published var localImage: UIImage?

    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, avatarUrl
        case caption, semanticPrompt, regionTags
        case userText, hasImage, createdAt
        case status, likeCount, isLikedByCurrentUser
    }

    // MARK: - Decode
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)

        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        semanticPrompt = try c.decodeIfPresent(String.self, forKey: .semanticPrompt)
        regionTags = try c.decodeIfPresent([RegionTag].self, forKey: .regionTags)
        userText = try c.decodeIfPresent(String.self, forKey: .userText)

        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount)

        if let bool = try? c.decode(Bool.self, forKey: .isLikedByCurrentUser) {
            isLikedByCurrentUser = bool
        } else if let int = try? c.decode(Int.self, forKey: .isLikedByCurrentUser) {
            isLikedByCurrentUser = (int != 0)
        } else {
            isLikedByCurrentUser = false
        }

        if let int = try? c.decode(Int.self, forKey: .hasImage) {
            hasImage = (int != 0)
        } else {
            hasImage = try c.decode(Bool.self, forKey: .hasImage)
        }

        if let ts = try? c.decode(Double.self, forKey: .createdAt) {
            createdAt = (ts > 10_000_000_000)
                ? Date(timeIntervalSince1970: ts / 1000)
                : Date(timeIntervalSince1970: ts)
        } else if let str = try? c.decode(String.self, forKey: .createdAt) {
            let iso = ISO8601DateFormatter()
            createdAt = iso.date(from: str)
                ?? Date()
        } else {
            createdAt = Date()
        }

        status = try c.decodeIfPresent(PostStatus.self, forKey: .status) ?? .normal

        localImage = nil
    }

    // MARK: - Create new
    init(
        id: String,
        userId: String?,
        displayName: String?,
        avatarUrl: String?,
        caption: String? = nil,
        semanticPrompt: String? = nil,
        regionTags: [RegionTag]? = nil,
        userText: String?,
        hasImage: Bool,
        status: PostStatus = .pending,
        createdAt: Date = Date(),
        localImage: UIImage? = nil
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.caption = caption
        self.semanticPrompt = semanticPrompt
        self.regionTags = regionTags
        self.userText = userText
        self.hasImage = hasImage
        self.status = status
        self.createdAt = createdAt
        self.localImage = localImage
        self.likeCount = 0
        self.isLikedByCurrentUser = false
    }
}

// MARK: - Encode
extension Post {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(userId ?? "", forKey: .userId)
        try c.encode(displayName ?? "", forKey: .displayName)
        try c.encode(avatarUrl ?? "", forKey: .avatarUrl)
        try c.encode(caption, forKey: .caption)
        try c.encode(semanticPrompt, forKey: .semanticPrompt)
        try c.encode(regionTags, forKey: .regionTags)
        try c.encode(userText, forKey: .userText)
        try c.encode(hasImage, forKey: .hasImage)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(status, forKey: .status)
        try c.encode(likeCount, forKey: .likeCount)
        try c.encode(isLikedByCurrentUser, forKey: .isLikedByCurrentUser)
    }
}
