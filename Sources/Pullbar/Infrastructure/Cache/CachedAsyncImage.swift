import SwiftUI

/// A simple in-memory image cache shared across the app lifetime.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Drop-in replacement for AsyncImage that checks an in-memory NSCache first.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        Group {
            if let cached = cachedImage {
                content(.success(Image(nsImage: cached)))
            } else {
                AsyncImage(url: url) { asyncPhase in
                    content(asyncPhase)
                        .onAppear {
                            if case .success = asyncPhase, let url {
                                // Render the SwiftUI Image to an NSImage for caching
                                cacheImage(from: url)
                            }
                        }
                }
            }
        }
    }

    private var cachedImage: NSImage? {
        guard let url else { return nil }
        return ImageCache.shared.image(for: url)
    }

    private func cacheImage(from url: URL) {
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let nsImage = NSImage(data: data) else { return }
            ImageCache.shared.store(nsImage, for: url)
        }
    }
}
