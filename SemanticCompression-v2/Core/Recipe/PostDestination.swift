import Foundation

nonisolated enum PostDestination {
    static func validatedID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                  (97...122).contains($0) || [45, 46, 95].contains($0) }) else { return nil }
        return value
    }

    static func postID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "mim", url.host?.lowercased() == "post",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let components = url.path.split(separator: "/")
        guard components.count == 1 else { return nil }
        return validatedID(String(components[0]))
    }

    static func postID(from payload: [AnyHashable: Any]) -> String? {
        for key in ["postId", "postID", "post_id"] {
            if let id = validatedID(payload[key] as? String) { return id }
        }
        if let value = payload["url"] as? String, let url = URL(string: value), let id = postID(from: url) { return id }
        if let data = payload["data"] as? [AnyHashable: Any] {
            for key in ["postId", "postID", "post_id"] {
                if let id = validatedID(data[key] as? String) { return id }
            }
        }
        return nil
    }

    static func followUserID(from payload: [AnyHashable: Any]) -> String? {
        guard payload["type"] as? String == "follow" else { return nil }
        return validatedID(payload["actorUserId"] as? String)
    }
}
