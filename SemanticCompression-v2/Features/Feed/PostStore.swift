//
//  PostStore.swift
//  SemanticCompression-v2
//
//  Created by Tasuku Kato on 2025/12/11.
//


import Foundation

actor PostStore {
    static let shared = PostStore()
    private init() {}

    private var map: [String: Post] = [:]

    /// サーバーから decode された Post を受け取り、
    /// 既存の Post があればそれを更新して返す。
    func resolve(_ incoming: Post) async -> Post {
        if let existing = map[incoming.id] {
            await MainActor.run {
                Self.applyUpdate(existing, with: incoming)
            }
            return existing
        } else {
            map[incoming.id] = incoming
            return incoming
        }
    }

    /// すでに UI が保持している Post を更新する（必要なフィールドだけ）
    @MainActor
    private static func applyUpdate(_ target: Post, with incoming: Post) {
        target.caption = incoming.caption
        target.semanticPrompt = incoming.semanticPrompt
        target.regionTags = incoming.regionTags
        target.tags = incoming.tags
        //target.userText = incoming.userText
        target.hasImage = incoming.hasImage
        target.likeCount = incoming.likeCount
        target.isLikedByCurrentUser = incoming.isLikedByCurrentUser
        target.commentCount = incoming.commentCount
        target.status = incoming.status
    }
}
