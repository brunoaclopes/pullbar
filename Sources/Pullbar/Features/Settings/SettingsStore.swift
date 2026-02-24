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
        static let showAuthorAvatar = "showAuthorAvatar"
        static let showPRNumber = "showPRNumber"
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

    @Published var showAuthorAvatar: Bool {
        didSet {
            defaults.set(showAuthorAvatar, forKey: Keys.showAuthorAvatar)
        }
    }

    @Published var showPRNumber: Bool {
        didSet {
            defaults.set(showPRNumber, forKey: Keys.showPRNumber)
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
        self.showAuthorAvatar = defaults.object(forKey: Keys.showAuthorAvatar) as? Bool ?? true
        self.showPRNumber = defaults.object(forKey: Keys.showPRNumber) as? Bool ?? true
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
        guard activeTabs.count < Self.maxTabs else { return }
        let number = tabs.filter { !$0.isDefault }.count + 1
        tabs.append(
            PRTabConfig(
                id: UUID().uuidString,
                title: "Custom \(number)",
                query: "is:open is:pr archived:false",
                isEnabled: true,
                defaultKind: nil,
                filterMatchMode: .all,
                filters: [],
                groupLevels: []
            )
        )
    }

    func removeCustomTab(id: String) {
        tabs.removeAll { $0.id == id && !$0.isDefault }
    }

    func moveTab(draggedId: String, to targetId: String) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == draggedId }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else {
            return
        }

        let movedTab = tabs.remove(at: fromIndex)
        tabs.insert(movedTab, at: toIndex)
    }

    func resetTabOrder() {
        let existingBuiltinsByKind: [BuiltinTabKind: PRTabConfig] = Dictionary(
            uniqueKeysWithValues: tabs.compactMap { tab in
                guard let kind = tab.defaultKind ?? BuiltinTabKind(rawValue: tab.id) else { return nil }
                return (kind, tab)
            }
        )

        let orderedBuiltins = BuiltinTabKind.allCases.map { kind -> PRTabConfig in
            if let existing = existingBuiltinsByKind[kind] {
                return PRTabConfig(
                    id: kind.rawValue,
                    title: kind.title,
                    query: Self.normalizeDefaultExtraQuery(existing.query, base: kind.defaultQuery),
                    isEnabled: existing.isEnabled,
                    defaultKind: kind,
                    filterMatchMode: .all,
                    filters: [],
                    groupLevels: existing.groupLevels
                )
            }

            return PRTabConfig(
                id: kind.rawValue,
                title: kind.title,
                query: "",
                isEnabled: true,
                defaultKind: kind,
                filterMatchMode: .all,
                filters: [],
                groupLevels: []
            )
        }

        let customTabs = tabs
            .filter { $0.defaultKind == nil && BuiltinTabKind(rawValue: $0.id) == nil }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        tabs = orderedBuiltins + customTabs
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
        let builtinIDs = Set(BuiltinTabKind.allCases.map(\.rawValue))
        var seenIDs = Set<String>()
        var seenBuiltins = Set<BuiltinTabKind>()
        var normalized: [PRTabConfig] = []

        for tab in input {
            if let kind = tab.defaultKind ?? BuiltinTabKind(rawValue: tab.id) {
                guard !seenBuiltins.contains(kind) else { continue }

                let extra = normalizeDefaultExtraQuery(tab.query, base: kind.defaultQuery)
                normalized.append(
                    PRTabConfig(
                        id: kind.rawValue,
                        title: kind.title,
                        query: extra,
                        isEnabled: tab.isEnabled,
                        defaultKind: kind,
                        filterMatchMode: .all,
                        filters: [],
                        groupLevels: tab.groupLevels
                    )
                )
                seenBuiltins.insert(kind)
                seenIDs.insert(kind.rawValue)
                continue
            }

            guard !builtinIDs.contains(tab.id), !seenIDs.contains(tab.id) else { continue }

            normalized.append(
                PRTabConfig(
                    id: tab.id,
                    title: tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom" : tab.title,
                    query: tab.query,
                    isEnabled: tab.isEnabled,
                    defaultKind: nil,
                    filterMatchMode: tab.filterMatchMode,
                    filters: sanitizeFilters(tab.filters),
                    groupLevels: tab.groupLevels
                )
            )
            seenIDs.insert(tab.id)
        }

        for kind in BuiltinTabKind.allCases where !seenBuiltins.contains(kind) {
            normalized.append(
                PRTabConfig(
                    id: kind.rawValue,
                    title: kind.title,
                    query: "",
                    isEnabled: true,
                    defaultKind: kind,
                    filterMatchMode: .all,
                    filters: [],
                    groupLevels: []
                )
            )
        }

        return normalized
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