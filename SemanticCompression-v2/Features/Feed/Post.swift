import Foundation
import UIKit
import Combine

enum PostStatus: String, Codable { case normal, pending, processing, completed, failed }
struct RegionTag: Codable { let region: String; let tags: [String] }

// Legacy guides are decoded for feed compatibility only, never generated or uploaded.
struct LowResGuide: Decodable { let jpegBase64: String? }
struct PostPayload: Decodable {
    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer().decode([String: LegacyJSONValue].self)
    }
}
private indirect enum LegacyJSONValue: Decodable {
    case string(String), number(Double), bool(Bool), array([LegacyJSONValue]), object([String: LegacyJSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([LegacyJSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: LegacyJSONValue].self)) }
    }
}

final class Post: Identifiable, ObservableObject, Codable {
    var id: String
    let userId: String?
    let displayName: String?
    let avatarUrl: String?
    @Published var caption: String?
    @Published var semanticPrompt: String?
    @Published var imageUnderstandingBackend: String?
    @Published var regionTags: [RegionTag]?
    @Published var recipe: GenerationRecipe?
    @Published var recipeReadError: String?
    let lowResGuide: LowResGuide?
    let mode: Int
    let payload: PostPayload?
    @Published var tags: [String]
    let userText: String?
    @Published var hasImage: Bool
    let createdAt: Date
    @Published var status: PostStatus
    @Published var likeCount: Int?
    @Published var isLikedByCurrentUser: Bool?
    @Published var commentCount: Int?
    @Published var localImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var imageGenerationFailed = false
    @Published var imageGenerationFailureReason: String?
    @Published var imageIsGenerating = false
    @Published var localPreparationMessage: String?
    var localImageRecipeKey: String?

    var effectivePrompt: String? { recipe?.prompt }
    var reconstructionUnavailableReason: String? {
        if let recipeReadError { return recipeReadError }
        if hasImage && recipe == nil {
            if status == .pending || status == .processing { return "写真を処理中" }
            if status == .failed { return "写真を処理できませんでした。" }
            return "この投稿の写真を再現できません。"
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, avatarUrl, caption, semanticPrompt, imageUnderstandingBackend, regionTags
        case userText, hasImage, createdAt, status, likeCount, isLikedByCurrentUser, commentCount
        case lowResGuide, mode, payload, tags, recipe
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName).map { ContentSafetyPolicy.displayText($0) }
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        caption = try c.decodeIfPresent(String.self, forKey: .caption).map { ContentSafetyPolicy.displayText($0) }
        semanticPrompt = try c.decodeIfPresent(String.self, forKey: .semanticPrompt)
        imageUnderstandingBackend = try c.decodeIfPresent(String.self, forKey: .imageUnderstandingBackend)
        regionTags = try c.decodeIfPresent([RegionTag].self, forKey: .regionTags)
        if c.contains(.recipe), !(try c.decodeNil(forKey: .recipe)) {
            do {
                let decoded = try c.decode(GenerationRecipe.self, forKey: .recipe)
                recipe = decoded
                try decoded.validate()
            } catch { recipeReadError = "この投稿の再現形式には対応していません。" }
        }
        lowResGuide = try? c.decode(LowResGuide.self, forKey: .lowResGuide)
        payload = try? c.decode(PostPayload.self, forKey: .payload)
        mode = (try? c.decode(Int.self, forKey: .mode)) ?? 1
        tags = ((try? c.decode([String].self, forKey: .tags)) ?? []).filter { (try? ContentSafetyPolicy.bundled().validate($0)) != nil }
        userText = try c.decodeIfPresent(String.self, forKey: .userText).map { ContentSafetyPolicy.displayText($0) }
        hasImage = (try? c.decode(Bool.self, forKey: .hasImage)) ?? ((try? c.decode(Int.self, forKey: .hasImage)) ?? 0 != 0)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount)
        isLikedByCurrentUser = (try? c.decode(Bool.self, forKey: .isLikedByCurrentUser)) ?? ((try? c.decode(Int.self, forKey: .isLikedByCurrentUser)) ?? 0 != 0)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount)
        createdAt = ServerDate.decodeDate(from: c, forKey: .createdAt)
        status = (try? c.decode(PostStatus.self, forKey: .status)) ?? .normal
    }

    init(id: String, userId: String?, displayName: String?, avatarUrl: String?,
         caption: String? = nil, semanticPrompt: String? = nil, imageUnderstandingBackend: String? = nil,
         recipe: GenerationRecipe? = nil, tags: [String] = [], userText: String?, hasImage: Bool,
         status: PostStatus = .pending, createdAt: Date = Date(), localImage: UIImage? = nil) {
        self.id = id; self.userId = userId; self.displayName = displayName; self.avatarUrl = avatarUrl
        self.caption = caption; self.semanticPrompt = semanticPrompt; self.imageUnderstandingBackend = imageUnderstandingBackend
        self.recipe = recipe; self.tags = tags; self.userText = userText; self.hasImage = hasImage
        self.createdAt = createdAt; self.status = status; self.localImage = localImage
        self.lowResGuide = nil; self.mode = 1; self.payload = nil
        self.likeCount = 0; self.isLikedByCurrentUser = false; self.commentCount = 0
        self.localImageRecipeKey = try? recipe?.cacheKey
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(semanticPrompt, forKey: .semanticPrompt)
        try c.encodeIfPresent(recipe, forKey: .recipe)
        try c.encodeIfPresent(userText, forKey: .userText)
        try c.encode(hasImage, forKey: .hasImage)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(likeCount, forKey: .likeCount)
        try c.encodeIfPresent(isLikedByCurrentUser, forKey: .isLikedByCurrentUser)
        try c.encodeIfPresent(commentCount, forKey: .commentCount)
        try c.encode(1, forKey: .mode)
        try c.encode(tags, forKey: .tags)
    }
}
