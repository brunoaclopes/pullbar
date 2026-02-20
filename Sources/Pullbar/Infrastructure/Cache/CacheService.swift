import Foundation

struct CacheService {
    private let fileManager = FileManager.default

    private var cacheURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appending(path: "Pullbar", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appending(path: "cache.json")
    }

    func load() -> PullRequestCache? {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return try? JSONDecoder().decode(PullRequestCache.self, from: data)
    }

    func save(_ cache: PullRequestCache) {
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }
        try? data.write(to: cacheURL, options: .atomic)
    }
}