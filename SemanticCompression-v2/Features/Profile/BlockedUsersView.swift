import SwiftUI

struct BlockedUsersView: View {
    @StateObject private var blockManager = BlockManager.shared
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var selectedLanguage = AppLanguage.japanese.rawValue
    @State private var userNames: [String: String] = [:]

    var body: some View {
        List {
            if blockManager.blockedUserIDs.isEmpty {
                Text(l("profile.blocked.empty"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(blockManager.blockedUserIDs).sorted(), id: \.self) { userId in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(userNames[userId] ?? l("profile.loading"))
                                .font(.subheadline)
                            Text(userId)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button(l("profile.blocked.unblock"), role: .destructive) {
                            Task {
                                await blockManager.unblock(userId)
                                userNames.removeValue(forKey: userId)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(l("profile.blocked.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await blockManager.refreshFromServerIfPossible()
            await loadDisplayNames()
        }
        .onChange(of: blockManager.blockedUserIDs) { _ in
            Task { await loadDisplayNames() }
        }
    }

    private func l(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.tr(key, languageCode: selectedLanguage, arguments: arguments)
    }

    private func loadDisplayNames() async {
        for userId in blockManager.blockedUserIDs where userNames[userId] == nil {
            do {
                let name = try await BlockService.fetchDisplayName(userId: userId)
                userNames[userId] = (name?.isEmpty == false) ? name : l("profile.unknown_user")
            } catch {
                userNames[userId] = l("profile.unknown_user")
            }
        }
    }
}
