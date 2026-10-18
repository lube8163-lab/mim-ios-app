#if DEBUG
import UIKit

/// Local synthetic fixtures, available only with the explicit offline review launch flag.
enum UIReviewFixtures {
    @MainActor
    static func photo() -> UIImage? {
        guard ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { return nil }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MimUIReview")
        return UIImage(contentsOfFile: root.appendingPathComponent("one-apple.png").path) ?? UIImage(named: "OnboardingPhoto")
    }
    @MainActor
    static func posts() -> [Post] {
        guard ProcessInfo.processInfo.arguments.contains("--mim-ui-review") else { return [] }
        let first = Post(id: "ui-review-photo", userId: nil, displayName: "haru", avatarUrl: nil,
                         caption: "窓からの光と、テーブルに置いたりんご。", userText: "朝の光がきれいだった。",
                         hasImage: true, status: .completed, createdAt: Date().addingTimeInterval(-240),
                         localImage: photo())
        first.likeCount = 12; first.commentCount = 2
        let second = Post(id: "ui-review-text", userId: nil, displayName: "nao", avatarUrl: nil,
                          userText: "帰り道、いつもと違う道を歩いてみた。\n少し遠回りするのもいいね。", hasImage: false,
                          status: .completed, createdAt: Date().addingTimeInterval(-960))
        second.likeCount = 5
        let third = Post(id: "ui-review-pending", userId: nil, displayName: "mio", avatarUrl: nil,
                         userText: "今日の一枚。", hasImage: true, status: .pending,
                         createdAt: Date().addingTimeInterval(-1_800))
        guard ProcessInfo.processInfo.arguments.contains("--mim-ui-review-long-feed") else {
            return [first, second, third]
        }
        let extra = (0..<20).map { index in
            Post(id: "ui-review-scroll-\(index)", userId: nil, displayName: "haru", avatarUrl: nil,
                 userText: "散歩の途中で見つけた景色。\n少しずつ日が長くなってきた。", hasImage: false,
                 status: .completed, createdAt: Date().addingTimeInterval(Double(-2_000 - index * 300)))
        }
        return [first, second, third] + extra
    }
}
#endif
