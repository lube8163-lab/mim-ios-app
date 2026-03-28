import Combine
import CryptoKit
import SwiftUI
import UIKit

final class AvatarImageStore {
    static let shared = AvatarImageStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = base.appendingPathComponent("AvatarCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for urlString: String) -> UIImage? {
        let key = urlString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: urlString))
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key)
        return image
    }

    func store(_ image: UIImage, for urlString: String) {
        let key = urlString as NSString
        memoryCache.setObject(image, forKey: key)

        let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: urlString))
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheFileName(for urlString: String) -> String {
        let digest = SHA256.hash(data: Data(urlString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}

@MainActor
final class CachedAvatarLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private var currentURLString = ""

    func load(urlString: String) async {
        guard !urlString.isEmpty else {
            image = nil
            currentURLString = ""
            return
        }

        if currentURLString != urlString {
            image = AvatarImageStore.shared.image(for: urlString)
            currentURLString = urlString
        }

        guard image == nil, let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard currentURLString == urlString,
                  let fetched = UIImage(data: data) else { return }
            AvatarImageStore.shared.store(fetched, for: urlString)
            image = fetched
        } catch {
            if image == nil {
                image = AvatarImageStore.shared.image(for: urlString)
            }
        }
    }
}

struct CachedAvatarView<Placeholder: View>: View {
    let urlString: String
    let placeholder: Placeholder

    @StateObject private var loader = CachedAvatarLoader()

    init(urlString: String, @ViewBuilder placeholder: () -> Placeholder) {
        self.urlString = urlString
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: urlString) {
            await loader.load(urlString: urlString)
        }
    }
}
