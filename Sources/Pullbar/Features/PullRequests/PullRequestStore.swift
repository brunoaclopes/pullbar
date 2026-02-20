import Foundation

@MainActor
final class PullRequestStore: ObservableObject {
    @Published private(set) var byTabId: [String: [PullRequestItem]] = [:]
    @Published private(set) var isRefreshing = false
    @Published var lastErrorMessage: String?
    @Published var lastUpdatedAt: Date?
    @Published private(set) var notificationHintCount = 0

    private let cache = CacheService()
    private let client = GitHubClient()
    private var autoRefreshTask: Task<Void, Never>?
    private var didLoadCache = false

    func configure(settings: SettingsStore) async {
        restartAutoRefresh(settings: settings)
        updateNotificationHints(settings: settings)
    }

    func loadCachedIfNeeded() async {
        guard !didLoadCache else { return }
        didLoadCache = true

        if let cached = cache.load() {
            byTabId = cached.byTabId
            lastUpdatedAt = cached.updatedAt
        } else {
            byTabId = [:]
        }
    }

    func refreshAll(force: Bool, settings: SettingsStore) async {
        guard !isRefreshing || force else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        var updated = byTabId
        var errors: [String] = []
        var successCount = 0

        let tabs = settings.activeTabs
        guard !tabs.isEmpty else {
            byTabId = [:]
            lastErrorMessage = nil
            notificationHintCount = 0
            return
        }

        let authToken: String
        do {
            authToken = try client.resolveToken()
        } catch {
            if let localized = error as? LocalizedError,
               let message = localized.errorDescription,
               !message.isEmpty {
                lastErrorMessage = message
            } else {
                lastErrorMessage = "GitHub token is missing. Add a Personal Access Token in Settings."
            }
            return
        }

        await withTaskGroup(of: (PRTabConfig, Result<[PullRequestItem], Error>).self) { group in
            for tab in tabs {
                let query = settings.effectiveQuery(for: tab)
                let apiURL = settings.resolvedGraphQLURL
                group.addTask {
                    do {
                        let prs = try await self.client.fetchPullRequests(query: query, graphQLURL: apiURL, token: authToken)
                        return (tab, .success(prs))
                    } catch {
                        return (tab, .failure(error))
                    }
                }
            }

            for await (tab, result) in group {
                switch result {
                case .success(let prs):
                    let filtered = applyTabFilters(prs, tab: tab)
                    updated[tab.id] = sortPullRequests(filtered, order: settings.prSortOrder)
                    successCount += 1
                case .failure(let error):
                    if let localized = error as? LocalizedError,
                       let message = localized.errorDescription,
                       !message.isEmpty {
                        errors.append("\(tab.title): \(message)")
                    } else {
                        errors.append("\(tab.title): Unable to refresh pull requests.")
                    }
                }
            }
        }

        if successCount > 0 {
            byTabId = updated
            lastUpdatedAt = Date()
            cache.save(PullRequestCache(updatedAt: lastUpdatedAt ?? Date(), byTabId: byTabId))
        }

        updateNotificationHints(settings: settings)

        if errors.isEmpty {
            lastErrorMessage = nil
        } else {
            lastErrorMessage = errors.joined(separator: "\n")
        }
    }

    func restartAutoRefresh(settings: SettingsStore) {
        autoRefreshTask?.cancel()
        let interval = max(60, settings.refreshIntervalSeconds)

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshAll(force: false, settings: settings)
            }
        }
    }

    func updateNotificationHints(settings: SettingsStore) {
        var count = 0

        if settings.notifyReviewRequests {
            if let reviewTab = settings.activeTabs.first(where: { $0.defaultKind == .reviewRequested }) {
                count += (byTabId[reviewTab.id] ?? []).count
            }
        }

        if settings.notifyOpenComments {
            var uniqueWithOpenComments = Set<String>()
            for prs in byTabId.values {
                for pr in prs where pr.unresolvedReviewThreads > 0 {
                    uniqueWithOpenComments.insert(pr.id)
                }
            }
            count += uniqueWithOpenComments.count
        }

        notificationHintCount = count
    }

    func applySort(settings: SettingsStore) {
        byTabId = byTabId.mapValues { sortPullRequests($0, order: settings.prSortOrder) }
        if let lastUpdatedAt {
            cache.save(PullRequestCache(updatedAt: lastUpdatedAt, byTabId: byTabId))
        }
    }

    private func sortPullRequests(_ items: [PullRequestItem], order: PRSortOrder) -> [PullRequestItem] {
        switch order {
        case .updatedDesc:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .createdDesc:
            return items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func applyTabFilters(_ items: [PullRequestItem], tab: PRTabConfig) -> [PullRequestItem] {
        guard !tab.filters.isEmpty else { return items }

        return items.filter { pr in
            switch tab.filterMatchMode {
            case .all:
                return tab.filters.allSatisfy { matchesFilter(pr: pr, filter: $0) }
            case .any:
                return tab.filters.contains { matchesFilter(pr: pr, filter: $0) }
            }
        }
    }

    private func matchesFilter(pr: PullRequestItem, filter: PRTabFilterRule) -> Bool {
        switch filter.value {
        case .hasUnresolvedComments:
            return pr.unresolvedReviewThreads > 0
        case .noUnresolvedComments:
            return pr.unresolvedReviewThreads == 0
        case .reviewApproved:
            return pr.reviewSummary == .approved
        case .reviewChangesRequested:
            return pr.reviewSummary == .changesRequested
        case .reviewRequired:
            return pr.reviewSummary == .reviewRequired
        case .reviewNone:
            return pr.reviewSummary == .none
        case .checksPassing:
            return pr.checkSummary == .passing
        case .checksFailing:
            return pr.checkSummary == .failing
        case .checksPending:
            return pr.checkSummary == .pending
        case .checksNone:
            return pr.checkSummary == .none
        }
    }

    deinit {
        autoRefreshTask?.cancel()
    }
}