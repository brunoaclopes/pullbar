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

struct PullRequestItem: Identifiable, Codable, Hashable {
    let id: String
    let number: Int
    let repository: String
    let title: String
    let author: String
    let createdAt: Date
    let updatedAt: Date
    let url: URL
    let reviewSummary: ReviewSummary
    let checkSummary: CheckSummary
    let unresolvedReviewThreads: Int
    let reviewThreadsTotal: Int

    var checksURL: URL {
        url.appending(path: "checks")
    }
}

struct PullRequestCache: Codable {
    let updatedAt: Date
    let byTabId: [String: [PullRequestItem]]
}
