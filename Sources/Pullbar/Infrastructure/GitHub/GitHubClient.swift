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
                let decoded: GraphQLResponse.DataContainer = try await executeGraphQL(
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
            ],
            graphQLURL: graphQLURL,
            token: token
        )
        let nodes = decoded.search.nodes
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
                reviewDetails: .empty,
                checkSummary: node.commits.nodes.first?.commit.statusCheckRollup?.state.toCheckSummary ?? .none,
                checks: [],
                unresolvedReviewThreads: node.reviewThreads.nodes.filter { !$0.isResolved }.count,
                reviewThreadsTotal: node.reviewThreads.totalCount,
                commentThreads: []
            )
        }

        return deduplicate(mapped).sorted(by: { $0.updatedAt > $1.updatedAt })
    }

        func estimatePullRequestSearchCost(query: String, graphQLURL: URL, token: String? = nil) async throws -> QueryCostEstimate {
                let data: PullRequestQueryCostData = try await executeGraphQL(
                        query: """
                        query PullRequestQueryCost($query: String!, $first: Int!) {
                            rateLimit(dryRun: true) {
                                cost
                                remaining
                                limit
                            }
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
                        ],
                        graphQLURL: graphQLURL,
                        token: token
                )

                return QueryCostEstimate(
                        cost: data.rateLimit.cost,
                        remaining: data.rateLimit.remaining,
                        limit: data.rateLimit.limit
                )
        }

        func fetchPullRequestChecks(nodeID: String, graphQLURL: URL, token: String? = nil) async throws -> [PullRequestCheck] {
                let data: PullRequestChecksData = try await executeGraphQL(
                        query: """
                        query PullRequestChecks($id: ID!) {
                            node(id: $id) {
                                ... on PullRequest {
                                    commits(last: 1) {
                                        nodes {
                                            commit {
                                                statusCheckRollup {
                                                    contexts(first: 100) {
                                                        nodes {
                                                            __typename
                                                            ... on CheckRun {
                                                                name
                                                                status
                                                                conclusion
                                                                detailsUrl
                                                                checkSuite {
                                                                    workflowRun {
                                                                        workflow {
                                                                            name
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            ... on StatusContext {
                                                                context
                                                                state
                                                                targetUrl
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        """,
                        variables: ["id": nodeID],
                        graphQLURL: graphQLURL,
                        token: token
                )

                return data.node?.pullRequestChecks ?? []
        }

        func fetchPullRequestCommentThreads(nodeID: String, graphQLURL: URL, token: String? = nil) async throws -> [PullRequestCommentThread] {
                let data: PullRequestCommentsData = try await executeGraphQL(
                        query: """
                        query PullRequestComments($id: ID!) {
                            node(id: $id) {
                                ... on PullRequest {
                                    reviewThreads(first: 100) {
                                        nodes {
                                            id
                                            isResolved
                                            isOutdated
                                            path
                                            line
                                            comments(first: 1) {
                                                nodes {
                                                    bodyText
                                                    url
                                                    author {
                                                        login
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        """,
                        variables: ["id": nodeID],
                        graphQLURL: graphQLURL,
                        token: token
                )

                return data.node?.pullRequestCommentThreads ?? []
        }

        func fetchPullRequestReviewDetails(nodeID: String, graphQLURL: URL, token: String? = nil) async throws -> PullRequestReviewDetails {
                let data: PullRequestReviewData = try await executeGraphQL(
                        query: """
                        query PullRequestReviewDetails($id: ID!) {
                            node(id: $id) {
                                ... on PullRequest {
                                    latestReviews(first: 100) {
                                        nodes {
                                            state
                                            submittedAt
                                            author {
                                                login
                                                avatarUrl
                                            }
                                        }
                                    }
                                    reviewRequests(first: 100) {
                                        pageInfo {
                                            hasNextPage
                                            endCursor
                                        }
                                        nodes {
                                            requestedReviewer {
                                                __typename
                                                ... on User {
                                                    login
                                                    avatarUrl
                                                }
                                                ... on Team {
                                                    name
                                                    avatarUrl
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        """,
                        variables: ["id": nodeID],
                        graphQLURL: graphQLURL,
                        token: token
                )

                guard let node = data.node else {
                        return .empty
                }

                var allReviewRequests = node.reviewRequests.nodes
                var hasNextPage = node.reviewRequests.pageInfo.hasNextPage
                var cursor = node.reviewRequests.pageInfo.endCursor

                while hasNextPage {
                        let nextPage: PullRequestReviewRequestsPageData = try await executeGraphQL(
                                query: """
                                query PullRequestReviewRequestsPage($id: ID!, $after: String) {
                                    node(id: $id) {
                                        ... on PullRequest {
                                            reviewRequests(first: 100, after: $after) {
                                                pageInfo {
                                                    hasNextPage
                                                    endCursor
                                                }
                                                nodes {
                                                    requestedReviewer {
                                                        __typename
                                                        ... on User {
                                                            login
                                                            avatarUrl
                                                        }
                                                        ... on Team {
                                                            name
                                                            avatarUrl
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                """,
                                variables: [
                                        "id": nodeID,
                                        "after": cursor as Any
                                ],
                                graphQLURL: graphQLURL,
                                token: token
                        )

                        guard let pageNode = nextPage.node else {
                                break
                        }

                        allReviewRequests.append(contentsOf: pageNode.reviewRequests.nodes)
                        hasNextPage = pageNode.reviewRequests.pageInfo.hasNextPage
                        cursor = pageNode.reviewRequests.pageInfo.endCursor
                }

                return node.toReviewDetails(allReviewRequests: allReviewRequests)
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

    private func executeGraphQL<T: Decodable>(
        query: String,
        variables: [String: Any],
        graphQLURL: URL,
        token: String?
    ) async throws -> T {
        let resolvedToken = try resolveToken(token)

        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedToken)", forHTTPHeaderField: "Authorization")

        let payload = GraphQLRequest(query: query, variables: variables)
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

        let decoded = try JSONDecoder().decode(GraphQLExecutionResponse<T>.self, from: data)
        if let firstError = decoded.errors?.first {
            throw GitHubClientError.graphql(firstError.message)
        }

        guard let payload = decoded.data else {
            throw GitHubClientError.invalidResponse
        }

        return payload
    }
}

struct QueryCostEstimate {
    let cost: Int
    let remaining: Int
    let limit: Int
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: EncodableValue]

    init(query: String, variables: [String: Any]) {
        self.query = query
        self.variables = variables.mapValues(EncodableValue.init)
    }
}

private struct GraphQLExecutionResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorMessage]?

    struct GraphQLErrorMessage: Decodable {
        let message: String
    }
}

private struct PullRequestQueryCostData: Decodable {
    let rateLimit: RateLimit

    struct RateLimit: Decodable {
        let cost: Int
        let remaining: Int
        let limit: Int
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

private struct PullRequestChecksData: Decodable {
    let node: Node?

    struct Node: Decodable {
        let commits: Commits

        struct Commits: Decodable {
            let nodes: [CommitNode]

            struct CommitNode: Decodable {
                let commit: Commit

                struct Commit: Decodable {
                    let statusCheckRollup: StatusCheckRollup?

                    struct StatusCheckRollup: Decodable {
                        let contexts: Contexts

                        struct Contexts: Decodable {
                            let nodes: [ContextNode]

                            struct ContextNode: Decodable {
                                let typeName: String
                                let name: String?
                                let status: String?
                                let conclusion: String?
                                let detailsUrl: String?
                                let checkSuite: CheckSuite?
                                let context: String?
                                let state: String?
                                let targetUrl: String?

                                private enum CodingKeys: String, CodingKey {
                                    case typeName = "__typename"
                                    case name
                                    case status
                                    case conclusion
                                    case detailsUrl
                                    case checkSuite
                                    case context
                                    case state
                                    case targetUrl
                                }

                                struct CheckSuite: Decodable {
                                    let workflowRun: WorkflowRun?

                                    struct WorkflowRun: Decodable {
                                        let workflow: Workflow?

                                        struct Workflow: Decodable {
                                            let name: String?
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension PullRequestChecksData.Node {
    var pullRequestChecks: [PullRequestCheck] {
        commits.nodes.first?.commit.statusCheckRollup?.contexts.nodes.compactMap { $0.toPullRequestCheck } ?? []
    }
}

private extension PullRequestChecksData.Node.Commits.CommitNode.Commit.StatusCheckRollup.Contexts.ContextNode {
    var toPullRequestCheck: PullRequestCheck? {
        if typeName == "CheckRun" {
            guard let name, let status = mapCheckRunStatus else {
                return nil
            }

            let category = checkSuite?.workflowRun?.workflow?.name ?? "GitHub Actions"
            return PullRequestCheck(
                id: "\(category)|\(name)",
                name: name,
                category: category,
                status: status,
                url: detailsUrl.flatMap(URL.init(string:))
            )
        }

        if typeName == "StatusContext" {
            guard let context, let status = mapStatusContextStatus else {
                return nil
            }

            return PullRequestCheck(
                id: "Status checks|\(context)",
                name: context,
                category: "Status checks",
                status: status,
                url: targetUrl.flatMap(URL.init(string:))
            )
        }

        return nil
    }

    private var mapCheckRunStatus: PullRequestCheckStatus? {
        switch conclusion {
        case "SUCCESS", "NEUTRAL", "SKIPPED":
            return .success
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE", "CANCELLED":
            return .failure
        default:
            switch status {
            case "COMPLETED":
                return .success
            case "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED", "EXPECTED":
                return .pending
            default:
                return nil
            }
        }
    }

    private var mapStatusContextStatus: PullRequestCheckStatus? {
        switch state {
        case "SUCCESS":
            return .success
        case "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE":
            return .failure
        case "PENDING", "EXPECTED":
            return .pending
        default:
            return nil
        }
    }
}

private struct PullRequestCommentsData: Decodable {
    let node: Node?

    struct Node: Decodable {
        let reviewThreads: ReviewThreads

        struct ReviewThreads: Decodable {
            let nodes: [ReviewThread]

            struct ReviewThread: Decodable {
                let id: String
                let isResolved: Bool
                let isOutdated: Bool
                let path: String?
                let line: Int?
                let comments: Comments

                struct Comments: Decodable {
                    let nodes: [Comment]

                    struct Comment: Decodable {
                        let bodyText: String?
                        let url: String?
                        let author: Author?

                        struct Author: Decodable {
                            let login: String
                        }
                    }
                }
            }
        }
    }
}

private extension PullRequestCommentsData.Node {
    var pullRequestCommentThreads: [PullRequestCommentThread] {
        reviewThreads.nodes.compactMap { $0.toPullRequestCommentThread }
    }
}

private extension PullRequestCommentsData.Node.ReviewThreads.ReviewThread {
    var toPullRequestCommentThread: PullRequestCommentThread? {
        let firstComment = comments.nodes.first
        let rawPreview = firstComment?.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = rawPreview.isEmpty ? "Open thread" : String(rawPreview.prefix(120))

        return PullRequestCommentThread(
            id: id,
            preview: preview,
            author: firstComment?.author?.login,
            path: path,
            line: line,
            status: isResolved ? .resolved : .unresolved,
            isOutdated: isOutdated,
            url: firstComment?.url.flatMap(URL.init(string:))
        )
    }
}

private struct PullRequestReviewData: Decodable {
    let node: Node?

    struct Node: Decodable {
        let latestReviews: LatestReviews
        let reviewRequests: ReviewRequests

        struct LatestReviews: Decodable {
            let nodes: [Review]

            struct Review: Decodable {
                let state: String?
                let submittedAt: String?
                let author: Author?

                struct Author: Decodable {
                    let login: String
                    let avatarUrl: String?
                }
            }
        }

        struct ReviewRequests: Decodable {
            let pageInfo: PageInfo
            let nodes: [ReviewRequest]

            struct PageInfo: Decodable {
                let hasNextPage: Bool
                let endCursor: String?
            }

            struct ReviewRequest: Decodable {
                let requestedReviewer: RequestedReviewer?

                struct RequestedReviewer: Decodable {
                    let typeName: String
                    let login: String?
                    let name: String?
                    let avatarUrl: String?

                    private enum CodingKeys: String, CodingKey {
                        case typeName = "__typename"
                        case login
                        case name
                        case avatarUrl
                    }
                }
            }
        }
    }
}

private struct PullRequestReviewRequestsPageData: Decodable {
    let node: PullRequestReviewData.Node?
}

private extension PullRequestReviewData.Node {
    func toReviewDetails(allReviewRequests: [ReviewRequests.ReviewRequest]? = nil) -> PullRequestReviewDetails {
        var latestByAuthor: [String: LatestReviews.Review] = [:]

        for review in latestReviews.nodes {
            guard let author = review.author?.login else {
                continue
            }

            guard let existing = latestByAuthor[author] else {
                latestByAuthor[author] = review
                continue
            }

            let existingDate = existing.submittedAt.flatMap(ISO8601DateFormatter.parseGitHubDate) ?? .distantPast
            let reviewDate = review.submittedAt.flatMap(ISO8601DateFormatter.parseGitHubDate) ?? .distantPast
            if reviewDate >= existingDate {
                latestByAuthor[author] = review
            }
        }

        let approvedBy = latestByAuthor
            .filter { $0.value.state == "APPROVED" }
            .map { login, review in
                PullRequestReviewActor(
                    login: login,
                    avatarURL: review.author?.avatarUrl.flatMap(URL.init(string:))
                )
            }
            .sortedByLogin

        let changesRequestedBy = latestByAuthor
            .filter { $0.value.state == "CHANGES_REQUESTED" }
            .map { login, review in
                PullRequestReviewActor(
                    login: login,
                    avatarURL: review.author?.avatarUrl.flatMap(URL.init(string:))
                )
            }
            .sortedByLogin

        let sourceRequests = allReviewRequests ?? reviewRequests.nodes
        let reviewRequestedFrom = sourceRequests.compactMap { request -> PullRequestReviewActor? in
            guard let reviewer = request.requestedReviewer else {
                return nil
            }

            if reviewer.typeName == "User" {
                guard let login = reviewer.login else {
                    return nil
                }
                return PullRequestReviewActor(
                    login: login,
                    avatarURL: reviewer.avatarUrl.flatMap(URL.init(string:))
                )
            }

            if reviewer.typeName == "Team" {
                guard let name = reviewer.name else {
                    return nil
                }
                return PullRequestReviewActor(
                    login: "@\(name)",
                    avatarURL: reviewer.avatarUrl.flatMap(URL.init(string:))
                )
            }

            return nil
        }
        .uniquedAndSortedByLogin

        return PullRequestReviewDetails(
            approvedBy: approvedBy,
            changesRequestedBy: changesRequestedBy,
            reviewRequestedFrom: reviewRequestedFrom
        )
    }
}

private extension Array where Element == PullRequestReviewActor {
    var sortedByLogin: [PullRequestReviewActor] {
        sorted { lhs, rhs in
            lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
        }
    }

    var uniquedAndSortedByLogin: [PullRequestReviewActor] {
        var byLogin: [String: PullRequestReviewActor] = [:]
        for actor in self {
            if byLogin[actor.login] == nil {
                byLogin[actor.login] = actor
            }
        }
        return Array(byLogin.values).sortedByLogin
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