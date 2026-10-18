import SwiftUI

struct AppInfoView: View {
    @AppStorage(AppPreferences.selectedLanguageKey)
    private var language = AppLanguage.preferred.rawValue

    var body: some View {
        let _ = language
        List {
            Section {
                Text("Mim").font(.title2.weight(.semibold))
                Text(mt("写真を言葉で届け、見る人の端末で再生成するSNSです。"))
                LabeledContent(mt("バージョン"), value: version)
            }
            Section(mt("写真とプライバシー")) {
                Text(mt("投稿に添付した元の写真は、サーバーに送りません。写真は端末内のAIで処理します。"))
                Text(mt("写真の説明と再生成に必要な情報は、投稿としてサーバーに保存されます。"))
                Text(mt("プロフィール画像はサーバーに保存され、ほかのユーザーに表示されます。"))
            }
            Section(mt("利用条件")) {
                Text(mt("画像の再現にはiOS 27.0.1以降・RAM 8 GB以上の対応端末が必要です。"))
                Text(mt("LFMを優先して使い、利用できないときはApple Foundation Modelsで処理します。"))
                Text(mt("AppleのAIを使う場合は、Apple Intelligenceを有効にしてください。"))
                Text(mt("モデルがなくても、文章の投稿や写真の説明を読むことから始められます。"))
                Text(mt("画像は見る人ごとに変わります。\n元の写真と見た目が変わることがあります。"))
            }
            Section {
                Link(mt("ソースコード"), destination: URL(string: "https://github.com/lube8163-lab/mim-ios-app")!)
            }
        }
        .navigationTitle(mt("アプリについて"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(MimStyle.paper)
    }
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}

