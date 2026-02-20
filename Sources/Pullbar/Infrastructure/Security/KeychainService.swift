import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case emptyToken
    case invalidData
    case unhandled(OSStatus)
}

struct KeychainService {
    private let service = "com.pullbar.token"
    private let account = "github-pat"
    private static var cachedToken: String?
    private static let cacheLock = NSLock()

    func readToken() throws -> String {
        if let cached = Self.withCacheLock({ Self.cachedToken }), !cached.isEmpty {
            return cached
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        Self.withCacheLock {
            Self.cachedToken = token
        }

        return token
    }

    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError.emptyToken
        }

        let tokenData = Data(trimmed.utf8)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: tokenData
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            Self.withCacheLock {
                Self.cachedToken = trimmed
            }
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = tokenData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
            Self.withCacheLock {
                Self.cachedToken = trimmed
            }
            return
        }

        throw KeychainError.unhandled(updateStatus)
    }

    func hasToken() -> Bool {
        do {
            let token = try readToken().trimmingCharacters(in: .whitespacesAndNewlines)
            return !token.isEmpty
        } catch {
            return false
        }
    }

    func deleteToken() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }

        Self.withCacheLock {
            Self.cachedToken = nil
        }
    }

    private static func withCacheLock<T>(_ body: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return body()
    }
}