import Foundation
import os

struct CacheService {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.pullbar", category: "CacheService")

    private var cacheURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appending(path: "Pullbar", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create cache directory: \(error.localizedDescription)")
            }
        }
        return folder.appending(path: "cache.json")
    }

    func load() -> PullRequestCache? {
        let data: Data
        do {
            data = try Data(contentsOf: cacheURL)
        } catch {
            logger.info("No cache file found or unreadable: \(error.localizedDescription)")
            return nil
        }
        do {
            return try JSONDecoder().decode(PullRequestCache.self, from: data)
        } catch {
            logger.warning("Cache decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ cache: PullRequestCache) {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            logger.error("Cache save failed: \(error.localizedDescription)")
        }
    }
}