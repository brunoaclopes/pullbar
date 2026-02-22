import Foundation

enum GitHubClientError: LocalizedError {
    case missingToken
    case unauthorized
    case rateLimited(resetAt: String?)
    case network
    case invalidResponse
    case graphql(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "GitHub token is missing. Add a Personal Access Token in Settings."
        case .unauthorized:
            return "Authentication failed. Verify your token and host URL."
        case .rateLimited(let resetAt):
            if let resetAt, let timestamp = TimeInterval(resetAt) {
                let date = Date(timeIntervalSince1970: timestamp)
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return "GitHub API rate limit reached. Try again after \(formatter.string(from: date))."
            }
            return "GitHub API rate limit reached. Try again later."
        case .network:
            return "Network request failed. Check your connection and host settings."
        case .invalidResponse:
            return "Received an invalid response from GitHub."
        case .graphql(let message):
            return message
        }
    }
}

struct GitHubClient {
    private let session: URLSession
    private let keychain: KeychainService

    init(session: URLSession = URLSession(configuration: {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return configuration
    }()), keychain: KeychainService = KeychainService()) {
        self.session = session
        self.keychain = keychain
    }

    func resolveToken() throws -> String {
        do {
            return try keychain.readToken()
        } catch KeychainError.itemNotFound {
            throw GitHubClientError.missingToken
        } catch {
            throw GitHubClientError.missingToken
        }
    }

    func fetchPullRequests(query: String, graphQLURL: URL, token: String? = nil) async throws -> [PullRequestItem] {
        let resolvedToken = try resolveToken(token)

        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedToken)", forHTTPHeaderField: "Authorization")

        let payload = GraphQLRequest(
            query: """
            query PullRequests($query: String!, $first: Int!) {
              search(type: ISSUE, query: $query, first: $first) {
                nodes {
                  ... on PullRequest {
                    id
                    number
                    title
                    url
                                        additions
                                        deletions
                    createdAt
                    updatedAt
                    reviewDecision
                    author {
                      login
                                            avatarUrl
                    }
                    repository {
                      nameWithOwner
                    }
                    commits(last: 1) {
                      nodes {
                        commit {
                          statusCheckRollup {
                            state
                          }
                        }
                      }
                    }
                                        reviewThreads(first: 100) {
                                            totalCount
                                            nodes {
                                                isResolved
                                            }
                                        }
                  }
                }
              }
            }
            """,
            variables: [
                "query": query,
                "first": 50
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubClientError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }

        if http.statusCode == 401 {
            throw GitHubClientError.unauthorized
        }

        if http.statusCode == 403,
           http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            throw GitHubClientError.rateLimited(resetAt: http.value(forHTTPHeaderField: "x-ratelimit-reset"))
        }

        guard (200..<300).contains(http.statusCode) else {
            throw GitHubClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(GraphQLResponse.self, from: data)

        if let firstError = decoded.errors?.first {
            throw GitHubClientError.graphql(firstError.message)
        }

        let nodes = decoded.data?.search.nodes ?? []
        let mapped = nodes.compactMap { node -> PullRequestItem? in
            guard
                let url = URL(string: node.url),
                let createdAt = ISO8601DateFormatter.parseGitHubDate(node.createdAt),
                let updatedAt = ISO8601DateFormatter.parseGitHubDate(node.updatedAt)
            else {
                return nil
            }

            return PullRequestItem(
                id: node.id,
                number: node.number,
                repository: node.repository.nameWithOwner,
                title: node.title,
                author: node.author?.login ?? "unknown",
                authorAvatarURL: node.author?.avatarUrl.flatMap(URL.init(string:)),
                additions: node.additions,
                deletions: node.deletions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                url: url,
                reviewSummary: node.reviewDecision.toSummary,
                checkSummary: node.commits.nodes.first?.commit.statusCheckRollup?.state.toCheckSummary ?? .none,
                unresolvedReviewThreads: node.reviewThreads.nodes.filter { !$0.isResolved }.count,
                reviewThreadsTotal: node.reviewThreads.totalCount
            )
        }

        return deduplicate(mapped).sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private func deduplicate(_ prs: [PullRequestItem]) -> [PullRequestItem] {
        var seen = Set<String>()
        var unique: [PullRequestItem] = []
        unique.reserveCapacity(prs.count)
        for pr in prs where seen.insert(pr.id).inserted {
            unique.append(pr)
        }
        return unique
    }

    private func resolveToken(_ token: String?) throws -> String {
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        return try resolveToken()
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: EncodableValue]

    init(query: String, variables: [String: Any]) {
        self.query = query
        self.variables = variables.mapValues(EncodableValue.init)
    }
}

private struct GraphQLResponse: Decodable {
    let data: DataContainer?
    let errors: [GraphQLError]?

    struct DataContainer: Decodable {
        let search: SearchResult
    }

    struct SearchResult: Decodable {
        let nodes: [PullRequestNode]
    }

    struct PullRequestNode: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: String
        let additions: Int
        let deletions: Int
        let createdAt: String
        let updatedAt: String
        let reviewDecision: String?
        let author: Author?
        let repository: Repository
        let commits: Commits
        let reviewThreads: ReviewThreads

        struct Author: Decodable {
            let login: String
            let avatarUrl: String?
        }

        struct Repository: Decodable {
            let nameWithOwner: String
        }

        struct Commits: Decodable {
            let nodes: [CommitNode]

            struct CommitNode: Decodable {
                let commit: Commit

                struct Commit: Decodable {
                    let statusCheckRollup: StatusCheckRollup?

                    struct StatusCheckRollup: Decodable {
                        let state: String?
                    }
                }
            }
        }

        struct ReviewThreads: Decodable {
            let totalCount: Int
            let nodes: [ReviewThread]

            struct ReviewThread: Decodable {
                let isResolved: Bool
            }
        }
    }

    struct GraphQLError: Decodable {
        let message: String
    }
}

private extension String? {
    var toSummary: ReviewSummary {
        switch self {
        case "APPROVED":
            return .approved
        case "CHANGES_REQUESTED":
            return .changesRequested
        case "REVIEW_REQUIRED":
            return .reviewRequired
        default:
            return .none
        }
    }

    var toCheckSummary: CheckSummary {
        switch self {
        case "SUCCESS":
            return .passing
        case "FAILURE", "ERROR", "STARTUP_FAILURE":
            return .failing
        case "PENDING", "EXPECTED":
            return .pending
        default:
            return .none
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseGitHubDate(_ value: String) -> Date? {
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }
        return withoutFractionalSeconds.date(from: value)
    }
}

private struct EncodableValue: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init(_ value: Any) {
        switch value {
        case let value as String:
            encodeValue = { try value.encode(to: $0) }
        case let value as Int:
            encodeValue = { try value.encode(to: $0) }
        case let value as Double:
            encodeValue = { try value.encode(to: $0) }
        case let value as Bool:
            encodeValue = { try value.encode(to: $0) }
        default:
            encodeValue = { encoder in
                var container = encoder.singleValueContainer()
                try container.encodeNil()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}