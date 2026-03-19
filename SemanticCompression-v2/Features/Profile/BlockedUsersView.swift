import SwiftUI

struct BlockedUsersView: View {
    @StateObject private var blockManager = BlockManager.shared
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var userNames: [String: String] = [:]

    var body: some View {
        List {
            if blockManager.blockedUserIDs.isEmpty {
                Text(t(ja: "現在ブロック中のユーザーはいません。", en: "No blocked users.", zh: "当前没有被屏蔽的用户。"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(blockManager.blockedUserIDs).sorted(), id: \.self) { userId in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(userNames[userId] ?? t(ja: "読み込み中...", en: "Loading...", zh: "加载中..."))
                                .font(.subheadline)
                            Text(userId)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(t(ja: "解除", en: "Unblock", zh: "解除屏蔽"), role: .destructive) {
                            Task {
                                await blockManager.unblock(userId)
                                userNames.removeValue(forKey: userId)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(t(ja: "ブロック管理", en: "Blocked Users", zh: "屏蔽管理"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await blockManager.refreshFromServerIfPossible()
            await loadDisplayNames()
        }
        .onChange(of: blockManager.blockedUserIDs) { _ in
            Task { await loadDisplayNames() }
        }
    }

    private func t(ja: String, en: String, zh: String? = nil) -> String {
        localizedText(languageCode: selectedLanguage, ja: ja, en: en, zh: zh)
    }

    private func loadDisplayNames() async {
        for userId in blockManager.blockedUserIDs where userNames[userId] == nil {
            do {
                let name = try await BlockService.fetchDisplayName(userId: userId)
                userNames[userId] = (name?.isEmpty == false) ? name : t(ja: "不明なユーザー", en: "Unknown User", zh: "未知用户")
            } catch {
                userNames[userId] = t(ja: "不明なユーザー", en: "Unknown User", zh: "未知用户")
            }
        }
    }
}
