import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let enterpriseHostURL = "enterpriseHostURL"
        static let enterpriseAPIURL = "enterpriseAPIURL"
        static let refreshInterval = "refreshInterval"
        static let notifyReviewRequests = "notifyReviewRequests"
        static let notifyOpenComments = "notifyOpenComments"
        static let showNotificationCount = "showNotificationCount"
        static let launchAtLogin = "launchAtLogin"
        static let prSortOrder = "prSortOrder"
        static let tabs = "tabs"
    }

    static let maxTabs = 5

    private let defaults = UserDefaults.standard

    @Published var enterpriseHostURL: String {
        didSet {
            defaults.set(Self.normalizedURLString(enterpriseHostURL), forKey: Keys.enterpriseHostURL)
        }
    }

    @Published var enterpriseAPIURL: String {
        didSet {
            defaults.set(Self.normalizedURLString(enterpriseAPIURL), forKey: Keys.enterpriseAPIURL)
        }
    }

    @Published var refreshIntervalSeconds: Int {
        didSet {
            defaults.set(max(60, min(refreshIntervalSeconds, 600)), forKey: Keys.refreshInterval)
        }
    }

    @Published var notifyReviewRequests: Bool {
        didSet {
            defaults.set(notifyReviewRequests, forKey: Keys.notifyReviewRequests)
        }
    }

    @Published var notifyOpenComments: Bool {
        didSet {
            defaults.set(notifyOpenComments, forKey: Keys.notifyOpenComments)
        }
    }

    @Published var showNotificationCount: Bool {
        didSet {
            defaults.set(showNotificationCount, forKey: Keys.showNotificationCount)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    @Published var prSortOrder: PRSortOrder {
        didSet {
            defaults.set(prSortOrder.rawValue, forKey: Keys.prSortOrder)
        }
    }

    @Published var tabs: [PRTabConfig] {
        didSet {
            persistTabs()
        }
    }

    init() {
        self.enterpriseHostURL = Self.normalizedURLString(defaults.string(forKey: Keys.enterpriseHostURL) ?? "")
        self.enterpriseAPIURL = Self.normalizedURLString(defaults.string(forKey: Keys.enterpriseAPIURL) ?? "")
        let savedRefresh = defaults.integer(forKey: Keys.refreshInterval)
        self.refreshIntervalSeconds = savedRefresh == 0 ? 90 : max(60, min(savedRefresh, 600))
        self.notifyReviewRequests = defaults.object(forKey: Keys.notifyReviewRequests) as? Bool ?? true
        self.notifyOpenComments = defaults.object(forKey: Keys.notifyOpenComments) as? Bool ?? true
        self.showNotificationCount = defaults.object(forKey: Keys.showNotificationCount) as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.prSortOrder = PRSortOrder(rawValue: defaults.string(forKey: Keys.prSortOrder) ?? "") ?? .updatedDesc
        self.tabs = Self.loadTabs(from: defaults)
    }

    var activeTabs: [PRTabConfig] {
        Array(tabs.filter { $0.isEnabled }.prefix(Self.maxTabs))
    }

    func effectiveQuery(for tab: PRTabConfig) -> String {
        if let kind = tab.defaultKind {
            let extra = tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if extra.isEmpty {
                return kind.defaultQuery
            }
            return "\(kind.defaultQuery) \(extra)"
        }

        return tab.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateTab(_ tab: PRTabConfig) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs[index] = tab
    }

    func addCustomTab() {
        guard tabs.count < Self.maxTabs else { return }
        let number = tabs.filter { !$0.isDefault }.count + 1
        tabs.append(
            PRTabConfig(
                id: UUID().uuidString,
                title: "Custom \(number)",
                query: "is:open is:pr archived:false",
                isEnabled: true,
                defaultKind: nil,
                filterMatchMode: .all,
                filters: []
            )
        )
    }

    func removeCustomTab(id: String) {
        tabs.removeAll { $0.id == id && !$0.isDefault }
    }

    var resolvedWebBaseURL: URL {
        let normalized = Self.normalizedURLString(enterpriseHostURL)
        guard !normalized.isEmpty else {
            return URL(string: "https://github.com")!
        }

        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return URL(string: normalized) ?? URL(string: "https://github.com")!
        }

        return URL(string: "https://\(normalized)") ?? URL(string: "https://github.com")!
    }

    var resolvedGraphQLURL: URL {
        let explicitAPI = Self.normalizedURLString(enterpriseAPIURL)
        if !explicitAPI.isEmpty {
            if explicitAPI.hasPrefix("http://") || explicitAPI.hasPrefix("https://") {
                return URL(string: explicitAPI) ?? URL(string: "https://api.github.com/graphql")!
            }
            return URL(string: "https://\(explicitAPI)") ?? URL(string: "https://api.github.com/graphql")!
        }

        let web = resolvedWebBaseURL
        if web.host == "github.com" {
            return URL(string: "https://api.github.com/graphql")!
        }
        return web.appending(path: "api/graphql")
    }

    private static func normalizedURLString(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func loadTabs(from defaults: UserDefaults) -> [PRTabConfig] {
        if let data = defaults.data(forKey: Keys.tabs),
           let decoded = try? JSONDecoder().decode([PRTabConfig].self, from: data),
           !decoded.isEmpty {
            return normalizeTabs(decoded)
        }

        return normalizeTabs([
            PRTabConfig(id: BuiltinTabKind.assignedToMe.rawValue, title: BuiltinTabKind.assignedToMe.title, query: BuiltinTabKind.assignedToMe.defaultQuery, isEnabled: true, defaultKind: .assignedToMe),
            PRTabConfig(id: BuiltinTabKind.reviewRequested.rawValue, title: BuiltinTabKind.reviewRequested.title, query: BuiltinTabKind.reviewRequested.defaultQuery, isEnabled: true, defaultKind: .reviewRequested),
            PRTabConfig(id: BuiltinTabKind.createdByMe.rawValue, title: BuiltinTabKind.createdByMe.title, query: BuiltinTabKind.createdByMe.defaultQuery, isEnabled: true, defaultKind: .createdByMe)
        ])
    }

    private func persistTabs() {
        let limited = Self.normalizeTabs(tabs)
        if limited.count != tabs.count {
            tabs = limited
            return
        }

        if let data = try? JSONEncoder().encode(limited) {
            defaults.set(data, forKey: Keys.tabs)
        }
    }

    private static func normalizeTabs(_ input: [PRTabConfig]) -> [PRTabConfig] {
        var normalizedDefaults: [PRTabConfig] = []

        for kind in BuiltinTabKind.allCases {
            if let existing = input.first(where: { $0.defaultKind == kind || $0.id == kind.rawValue }) {
                let extra = normalizeDefaultExtraQuery(existing.query, base: kind.defaultQuery)
                normalizedDefaults.append(
                    PRTabConfig(
                        id: kind.rawValue,
                        title: kind.title,
                        query: extra,
                        isEnabled: existing.isEnabled,
                        defaultKind: kind,
                        filterMatchMode: .all,
                        filters: []
                    )
                )
            } else {
                normalizedDefaults.append(
                    PRTabConfig(
                        id: kind.rawValue,
                        title: kind.title,
                        query: "",
                        isEnabled: true,
                        defaultKind: kind,
                        filterMatchMode: .all,
                        filters: []
                    )
                )
            }
        }

        let customTabs = input
            .filter { $0.defaultKind == nil && !BuiltinTabKind.allCases.map(\.rawValue).contains($0.id) }
            .map {
                PRTabConfig(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : $0.title,
                    query: $0.query,
                    isEnabled: $0.isEnabled,
                    defaultKind: nil,
                    filterMatchMode: $0.filterMatchMode,
                    filters: sanitizeFilters($0.filters)
                )
            }

        return Array((normalizedDefaults + customTabs).prefix(maxTabs))
    }

    private static func normalizeDefaultExtraQuery(_ query: String, base: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTrimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == baseTrimmed {
            return ""
        }

        if trimmed.hasPrefix(baseTrimmed + " ") {
            return String(trimmed.dropFirst(baseTrimmed.count + 1))
        }

        return trimmed
    }

    private static func sanitizeFilters(_ filters: [PRTabFilterRule]) -> [PRTabFilterRule] {
        filters.compactMap { filter in
            guard filter.field.allowedValues.contains(filter.value) else { return nil }
            return filter
        }
    }
}