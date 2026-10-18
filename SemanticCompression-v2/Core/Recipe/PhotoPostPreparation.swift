import Foundation

/// Durable metadata for a photo post. The source photo is kept in the app's private container.
nonisolated struct PhotoPostPreparation: Codable, Identifiable, Sendable {
    enum Stage: String, Codable, Sendable { case queued, accepted, described, failed }
    let id: String
    let ownerID: String
    let displayName: String
    let avatarURL: String
    let userText: String
    let createdAt: Date
    var stage: Stage = .queued
    var accepted = false
    var caption: String?
    var tags: [String] = []
    var understandingBackend: String?
    var recipe: GenerationRecipe?
    var message: String?

    var pendingPayload: PendingPhotoPostPayload {
        .init(clientPostID: id, userText: userText)
    }
    mutating func retry() {
        stage = recipe != nil ? .described : accepted ? .accepted : .queued
        message = nil
    }
}

// Only text, recipe metadata, and a client-generated id may leave the device.
nonisolated struct PendingPhotoPostPayload: Encodable, Sendable {
    let mode = 1
    let hasImage = true
    let photoProcessing = "pending"
    let tags: [String] = []
    let clientPostID: String
    let userText: String
}

nonisolated struct CompletePhotoPostPayload: Encodable, Sendable {
    let id: String
    let status = "completed"
    let caption: String?
    let semanticPrompt: String
    let tags: [String]
    let imageUnderstandingBackend: String?
    let recipe: GenerationRecipe
}
