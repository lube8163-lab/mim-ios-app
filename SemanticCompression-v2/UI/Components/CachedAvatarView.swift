import Combine
import CryptoKit
import SwiftUI
import UIKit

@MainActor
final class AvatarImageStore {
    static let shared = AvatarImageStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // The old cache may contain bytes that have never been classified.
        cacheDirectory = base.appendingPathComponent("AvatarCache-safe-v2", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for urlString: String) async throws -> UIImage? {
        let key = urlString as NSString
        if let cached = memoryCache.object(forKey: key) {
            try await ImageSafetyService.check(cached)
            return cached
        }

        let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: urlString))
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        do { try await ImageSafetyService.check(image) }
        catch { remove(for: urlString); throw error }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    func store(_ image: UIImage, for urlString: String) async throws {
        try await ImageSafetyService.check(image)
        let key = urlString as NSString
        memoryCache.setObject(image, forKey: key)

        let fileURL = cacheDirectory.appendingPathComponent(cacheFileName(for: urlString))
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func remove(for urlString: String) {
        memoryCache.removeObject(forKey: urlString as NSString)
        try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(cacheFileName(for: urlString)))
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

        image = nil
        currentURLString = urlString
        do {
            if let cached = try await AvatarImageStore.shared.image(for: urlString) {
                guard currentURLString == urlString, !Task.isCancelled else { return }
                image = cached
                return
            }
            guard let url = URL(string: urlString), url.scheme == "https" else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 5 * 1024 * 1024 else { throw URLError(.badServerResponse) }
            guard currentURLString == urlString,
                  let fetched = UIImage(data: data) else { return }
            try await AvatarImageStore.shared.store(fetched, for: urlString)
            guard currentURLString == urlString, !Task.isCancelled else { return }
            image = fetched
        } catch {
            // Neither a blocked cached image nor a classifier error may fall back to
            // unverified bytes. Keep the placeholder and allow a future retry.
            if currentURLString == urlString {
                image = nil
                AvatarImageStore.shared.remove(for: urlString)
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
