import Foundation

enum PRSortOrder: String, CaseIterable, Codable, Identifiable {
    case updatedDesc
    case createdDesc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updatedDesc:
            return "Updated"
        case .createdDesc:
            return "Created"
        }
    }
}

enum BuiltinTabKind: String, CaseIterable, Codable {
    case assignedToMe
    case reviewRequested
    case createdByMe

    var title: String {
        switch self {
        case .assignedToMe:
            return "Assigned"
        case .reviewRequested:
            return "Review"
        case .createdByMe:
            return "Created"
        }
    }

    var defaultQuery: String {
        switch self {
        case .assignedToMe:
            return "is:open is:pr archived:false assignee:@me"
        case .reviewRequested:
            return "is:open is:pr archived:false review-requested:@me"
        case .createdByMe:
            return "is:open is:pr archived:false author:@me"
        }
    }
}

struct PRTabConfig: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var query: String
    var isEnabled: Bool
    let defaultKind: BuiltinTabKind?
    var filterMatchMode: PRTabFilterMatchMode
    var filters: [PRTabFilterRule]

    init(
        id: String,
        title: String,
        query: String,
        isEnabled: Bool,
        defaultKind: BuiltinTabKind?,
        filterMatchMode: PRTabFilterMatchMode = .all,
        filters: [PRTabFilterRule] = []
    ) {
        self.id = id
        self.title = title
        self.query = query
        self.isEnabled = isEnabled
        self.defaultKind = defaultKind
        self.filterMatchMode = filterMatchMode
        self.filters = filters
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
        case isEnabled
        case defaultKind
        case filterMatchMode
        case filters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        query = try container.decode(String.self, forKey: .query)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        defaultKind = try container.decodeIfPresent(BuiltinTabKind.self, forKey: .defaultKind)
        filterMatchMode = try container.decodeIfPresent(PRTabFilterMatchMode.self, forKey: .filterMatchMode) ?? .all
        filters = try container.decodeIfPresent([PRTabFilterRule].self, forKey: .filters) ?? []
    }

    var isDefault: Bool {
        defaultKind != nil
    }
}

enum PRTabFilterMatchMode: String, CaseIterable, Codable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Match all"
        case .any:
            return "Match any"
        }
    }
}

enum PRTabFilterField: String, CaseIterable, Codable, Identifiable {
    case unresolvedComments
    case reviewStatus
    case checksStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unresolvedComments:
            return "Comments"
        case .reviewStatus:
            return "Review"
        case .checksStatus:
            return "Checks"
        }
    }

    var allowedValues: [PRTabFilterValue] {
        switch self {
        case .unresolvedComments:
            return [.hasUnresolvedComments, .noUnresolvedComments]
        case .reviewStatus:
            return [.reviewApproved, .reviewChangesRequested, .reviewRequired, .reviewNone]
        case .checksStatus:
            return [.checksPassing, .checksFailing, .checksPending, .checksNone]
        }
    }
}

enum PRTabFilterValue: String, CaseIterable, Codable, Identifiable {
    case hasUnresolvedComments
    case noUnresolvedComments
    case reviewApproved
    case reviewChangesRequested
    case reviewRequired
    case reviewNone
    case checksPassing
    case checksFailing
    case checksPending
    case checksNone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hasUnresolvedComments:
            return "Has unresolved"
        case .noUnresolvedComments:
            return "No unresolved"
        case .reviewApproved:
            return "Approved"
        case .reviewChangesRequested:
            return "Changes requested"
        case .reviewRequired:
            return "Review required"
        case .reviewNone:
            return "No review"
        case .checksPassing:
            return "Passing"
        case .checksFailing:
            return "Failing"
        case .checksPending:
            return "Pending"
        case .checksNone:
            return "No checks"
        }
    }
}

struct PRTabFilterRule: Identifiable, Codable, Hashable {
    var id: String
    var field: PRTabFilterField
    var value: PRTabFilterValue

    init(id: String = UUID().uuidString, field: PRTabFilterField, value: PRTabFilterValue) {
        self.id = id
        self.field = field
        self.value = value
    }

    static func `default`() -> PRTabFilterRule {
        PRTabFilterRule(field: .unresolvedComments, value: .hasUnresolvedComments)
    }
}

enum ReviewSummary: String, Codable {
    case approved
    case changesRequested
    case reviewRequired
    case none

    var text: String {
        switch self {
        case .approved:
            return "Approved"
        case .changesRequested:
            return "Changes requested"
        case .reviewRequired:
            return "Review required"
        case .none:
            return "No review"
        }
    }
}

struct PullRequestReviewDetails: Codable, Hashable {
    let approvedBy: [PullRequestReviewActor]
    let changesRequestedBy: [PullRequestReviewActor]
    let reviewRequestedFrom: [PullRequestReviewActor]

    private enum CodingKeys: String, CodingKey {
        case approvedBy
        case changesRequestedBy
        case reviewRequestedFrom
    }

    static let empty = PullRequestReviewDetails(
        approvedBy: [],
        changesRequestedBy: [],
        reviewRequestedFrom: []
    )

    init(
        approvedBy: [PullRequestReviewActor],
        changesRequestedBy: [PullRequestReviewActor],
        reviewRequestedFrom: [PullRequestReviewActor]
    ) {
        self.approvedBy = approvedBy
        self.changesRequestedBy = changesRequestedBy
        self.reviewRequestedFrom = reviewRequestedFrom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let approvedActors = try? container.decode([PullRequestReviewActor].self, forKey: .approvedBy),
           let changesActors = try? container.decode([PullRequestReviewActor].self, forKey: .changesRequestedBy),
           let requestedActors = try? container.decode([PullRequestReviewActor].self, forKey: .reviewRequestedFrom) {
            approvedBy = approvedActors
            changesRequestedBy = changesActors
            reviewRequestedFrom = requestedActors
            return
        }

        let approvedNames = (try? container.decode([String].self, forKey: .approvedBy)) ?? []
        let changesNames = (try? container.decode([String].self, forKey: .changesRequestedBy)) ?? []
        let requestedNames = (try? container.decode([String].self, forKey: .reviewRequestedFrom)) ?? []

        approvedBy = approvedNames.map { PullRequestReviewActor(login: $0, avatarURL: nil) }
        changesRequestedBy = changesNames.map { PullRequestReviewActor(login: $0, avatarURL: nil) }
        reviewRequestedFrom = requestedNames.map { PullRequestReviewActor(login: $0, avatarURL: nil) }
    }
}

struct PullRequestReviewActor: Identifiable, Codable, Hashable {
    let login: String
    let avatarURL: URL?

    var id: String { login }
}

enum CheckSummary: String, Codable {
    case passing
    case failing
    case pending
    case none

    var text: String {
        switch self {
        case .passing:
            return "Checks passing"
        case .failing:
            return "Checks failing"
        case .pending:
            return "Checks pending"
        case .none:
            return "No checks"
        }
    }
}

enum PullRequestCheckStatus: String, Codable {
    case success
    case failure
    case pending

    var text: String {
        switch self {
        case .success:
            return "Success"
        case .failure:
            return "Failed"
        case .pending:
            return "Pending"
        }
    }
}

struct PullRequestCheck: Identifiable, Codable, Hashable {
    var id: String
    let name: String
    let category: String
    let status: PullRequestCheckStatus
    let url: URL?

    init(id: String = UUID().uuidString, name: String, category: String, status: PullRequestCheckStatus, url: URL? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.status = status
        self.url = url
    }
}

enum PullRequestCommentThreadStatus: String, Codable {
    case unresolved
    case resolved

    var text: String {
        switch self {
        case .unresolved:
            return "Open"
        case .resolved:
            return "Resolved"
        }
    }
}

struct PullRequestCommentThread: Identifiable, Codable, Hashable {
    let id: String
    let preview: String
    let author: String?
    let path: String?
    let line: Int?
    let status: PullRequestCommentThreadStatus
    let isOutdated: Bool
    let url: URL?
}

struct PullRequestItem: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let repository: String
    let title: String
    let author: String
    let authorAvatarURL: URL?
    let additions: Int
    let deletions: Int
    let createdAt: Date
    let updatedAt: Date
    let url: URL
    let reviewSummary: ReviewSummary
    let reviewDetails: PullRequestReviewDetails
    let checkSummary: CheckSummary
    let checks: [PullRequestCheck]
    let unresolvedReviewThreads: Int
    let reviewThreadsTotal: Int
    let commentThreads: [PullRequestCommentThread]

    var checksURL: URL {
        url.appending(path: "checks")
    }

    var filesURL: URL {
        url.appending(path: "files")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case repository
        case title
        case author
        case authorAvatarURL
        case additions
        case deletions
        case createdAt
        case updatedAt
        case url
        case reviewSummary
        case reviewDetails
        case checkSummary
        case checks
        case unresolvedReviewThreads
        case reviewThreadsTotal
        case commentThreads
    }

    init(
        id: String,
        number: Int,
        repository: String,
        title: String,
        author: String,
        authorAvatarURL: URL? = nil,
        additions: Int,
        deletions: Int,
        createdAt: Date,
        updatedAt: Date,
        url: URL,
        reviewSummary: ReviewSummary,
        reviewDetails: PullRequestReviewDetails = .empty,
        checkSummary: CheckSummary,
        checks: [PullRequestCheck],
        unresolvedReviewThreads: Int,
        reviewThreadsTotal: Int,
        commentThreads: [PullRequestCommentThread] = []
    ) {
        self.id = id
        self.number = number
        self.repository = repository
        self.title = title
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.additions = additions
        self.deletions = deletions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.reviewSummary = reviewSummary
        self.reviewDetails = reviewDetails
        self.checkSummary = checkSummary
        self.checks = checks
        self.unresolvedReviewThreads = unresolvedReviewThreads
        self.reviewThreadsTotal = reviewThreadsTotal
        self.commentThreads = commentThreads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        repository = try container.decode(String.self, forKey: .repository)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        authorAvatarURL = try container.decodeIfPresent(URL.self, forKey: .authorAvatarURL)
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        url = try container.decode(URL.self, forKey: .url)
        reviewSummary = try container.decode(ReviewSummary.self, forKey: .reviewSummary)
        reviewDetails = try container.decodeIfPresent(PullRequestReviewDetails.self, forKey: .reviewDetails) ?? .empty
        checkSummary = try container.decode(CheckSummary.self, forKey: .checkSummary)
        checks = try container.decodeIfPresent([PullRequestCheck].self, forKey: .checks) ?? []
        unresolvedReviewThreads = try container.decode(Int.self, forKey: .unresolvedReviewThreads)
        reviewThreadsTotal = try container.decode(Int.self, forKey: .reviewThreadsTotal)
        commentThreads = try container.decodeIfPresent([PullRequestCommentThread].self, forKey: .commentThreads) ?? []
    }
}

extension PullRequestItem {
    func updating(
        reviewDetails: PullRequestReviewDetails? = nil,
        checks: [PullRequestCheck]? = nil,
        commentThreads: [PullRequestCommentThread]? = nil,
        unresolvedReviewThreads: Int? = nil,
        reviewThreadsTotal: Int? = nil
    ) -> PullRequestItem {
        PullRequestItem(
            id: id,
            number: number,
            repository: repository,
            title: title,
            author: author,
            authorAvatarURL: authorAvatarURL,
            additions: additions,
            deletions: deletions,
            createdAt: createdAt,
            updatedAt: updatedAt,
            url: url,
            reviewSummary: reviewSummary,
            reviewDetails: reviewDetails ?? self.reviewDetails,
            checkSummary: checkSummary,
            checks: checks ?? self.checks,
            unresolvedReviewThreads: unresolvedReviewThreads ?? self.unresolvedReviewThreads,
            reviewThreadsTotal: reviewThreadsTotal ?? self.reviewThreadsTotal,
            commentThreads: commentThreads ?? self.commentThreads
        )
    }
}

struct PullRequestCache: Codable {
    let updatedAt: Date
    let byTabId: [String: [PullRequestItem]]
}
