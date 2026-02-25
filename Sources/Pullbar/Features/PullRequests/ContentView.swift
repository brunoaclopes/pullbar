import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: PullRequestStore

    @State private var selectedTabId: String = ""
    @State private var hasToken = false
    @State private var setupMessage = ""
    @State private var isShowingSettings = false
    @State private var tabTransitionDirection: Edge = .trailing

    private let keychain = KeychainService()

    var body: some View {
        VStack(spacing: 10) {
            header
            Divider()
            bodyContent
        }
        .padding(12)
        .onAppear {
            refreshTokenState()
            ensureSelectedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTokenState()
        }
        .onChange(of: settings.tabs) { _, _ in
            ensureSelectedTab()
        }
        .keyboardShortcut("r", modifiers: .command)  // Cmd+R: dummy, handled below
        .background {
            // Invisible buttons that capture keyboard shortcuts
            Button("") { Task { await store.refreshAll(force: true) } }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
            Button("") { isShowingSettings.toggle() }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
            Button("") { switchTab(direction: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden()
            Button("") { switchTab(direction: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if isShowingSettings {
                settingsHeader
            } else {
                tabsHeader
            }

            if !isShowingSettings {
                Button {
                    Task {
                        await store.refreshAll(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .background(Color.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help("Refresh")
                .disabled(!hasToken || store.isRefreshing)

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .background(Color.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help("Settings")
            }
        }
    }

    private var tabsHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(settings.activeTabs) { tab in
                    let isSelected = selectedTabId == tab.id
                    Button {
                        updateTransitionDirection(for: tab.id)
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedTabId = tab.id
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.title)
                                .lineLimit(1)
                            Text("\(store.byTabId[tab.id, default: []].count)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(isSelected ? Color.accentColor : Color.clear)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button {
                isShowingSettings = false
            } label: {
                Label("Back to list", systemImage: "chevron.left")
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Text("Settings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var bodyContent: some View {
        if isShowingSettings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(store)
                .onDisappear {
                    refreshTokenState()
                }
        } else if !hasToken {
            VStack(alignment: .leading, spacing: 12) {
                Label("Set up required", systemImage: "key.fill")
                    .font(.headline)
                Text("Add a GitHub Personal Access Token in Settings to start syncing pull requests.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Settings") {
                        openSettingsWindow()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("I added token, refresh") {
                        refreshTokenState()
                        guard hasToken else {
                            setupMessage = "Token not found yet. Save it in Settings first."
                            return
                        }
                        setupMessage = ""
                        Task {
                            await store.refreshAll(force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if !setupMessage.isEmpty {
                    Text(setupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let error = store.lastErrorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sync failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await store.refreshAll(force: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if selectedTabItems.isEmpty {
            emptyTabState
        } else {
            if selectedTabGroupLevels.isEmpty {
                ungroupedListView
            } else {
                groupedListView
            }
        }

        footer
    }

    private var footer: some View {
        HStack {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if let updated = store.lastUpdatedAt {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyTabState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    Text("No pull requests in \(selectedTabTitle)")
                        .font(.headline)
                    Text("Try refreshing or updating this tab query and rules.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Button("Refresh") {
                        Task {
                            await store.refreshAll(force: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Edit tabs") {
                        isShowingSettings = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedTabTitle: String {
        settings.activeTabs.first(where: { $0.id == selectedTabId })?.title ?? "this tab"
    }

    private func refreshTokenState() {
        hasToken = keychain.hasToken()
        if hasToken {
            setupMessage = ""
        }
    }

    private func openSettingsWindow() {
        setupMessage = ""
        isShowingSettings = true
    }

    private var selectedTabItems: [PullRequestItem] {
        store.byTabId[selectedTabId] ?? []
    }

    private var selectedTabConfig: PRTabConfig? {
        settings.activeTabs.first(where: { $0.id == selectedTabId })
    }

    private var selectedTabGroupLevels: [PRTabGroupLevel] {
        selectedTabConfig?.groupLevels ?? []
    }

    private var groupedSelectedTabItems: [PullRequestGroupSection] {
        let levels = selectedTabGroupLevels
        guard !levels.isEmpty else { return [] }
        return makeGroups(items: selectedTabItems, levels: levels)
    }

    private func makeGroups(items: [PullRequestItem], levels: [PRTabGroupLevel]) -> [PullRequestGroupSection] {
        guard let level = levels.first else { return [] }
        let remaining = Array(levels.dropFirst())
        let groups = Dictionary(grouping: items) { groupKey($0, by: level.grouping) }
        let sortedKeys = sortGroupKeys(Array(groups.keys), grouping: level.grouping, order: level.order)
        return sortedKeys.compactMap { key in
            guard let groupItems = groups[key] else { return nil }
            if remaining.isEmpty {
                return PullRequestGroupSection(key: key, items: groupItems, subgroups: [])
            } else {
                return PullRequestGroupSection(key: key, items: [], subgroups: makeGroups(items: groupItems, levels: remaining))
            }
        }
    }

    private func groupKey(_ pr: PullRequestItem, by grouping: PRTabGrouping) -> String {
        switch grouping {
        case .none:        return ""
        case .repository:  return pr.repository
        case .author:      return pr.author
        case .reviewStatus: return pr.reviewSummary.text
        case .checksStatus: return pr.checkSummary.text
        case .draft:       return pr.isDraft ? "Draft" : "Ready"
        case .age:         return ageGroup(for: pr.updatedAt)
        }
    }

    private func ageGroup(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)),
           date >= weekAgo { return "This week" }
        if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
           date >= monthAgo { return "This month" }
        return "Older"
    }

    private func sortGroupKeys(_ keys: [String], grouping: PRTabGrouping, order: PRTabGroupingOrder) -> [String] {
        switch grouping {
        case .none:
            return keys
        case .repository, .author:
            return keys.sorted {
                let cmp = $0.localizedCaseInsensitiveCompare($1)
                return order == .ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .reviewStatus:
            return sortByIndex(keys, order: order) { ReviewSummary.sortIndex(forText: $0) }
        case .checksStatus:
            return sortByIndex(keys, order: order) { CheckSummary.sortIndex(forText: $0) }
        case .draft:
            let priorities = ["Ready": 0, "Draft": 1]
            return sortByIndex(keys, order: order) { priorities[$0] ?? 99 }
        case .age:
            let priorities = ["Today": 0, "Yesterday": 1, "This week": 2, "This month": 3, "Older": 4]
            return sortByIndex(keys, order: order) { priorities[$0] ?? 99 }
        }
    }

    private func sortByIndex(_ keys: [String], order: PRTabGroupingOrder, index: (String) -> Int) -> [String] {
        keys.sorted { order == .ascending ? index($0) < index($1) : index($0) > index($1) }
    }

    private var ungroupedListView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            List(selectedTabItems) { pr in
                PullRequestRow(pr: pr)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(.vertical, 8)
            .id(selectedTabId)
            .transition(.asymmetric(
                insertion: .move(edge: tabTransitionDirection).combined(with: .opacity),
                removal: .move(edge: tabTransitionDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.22), value: selectedTabId)
        .listStyle(.plain)
    }

    private var groupedListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(groupedSelectedTabItems) { group in
                    PullRequestGroupCard(group: group)
                }
            }
        }
        .id(selectedTabId)
        .transition(.asymmetric(
            insertion: .move(edge: tabTransitionDirection).combined(with: .opacity),
            removal: .move(edge: tabTransitionDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
        ))
        .animation(.easeInOut(duration: 0.22), value: selectedTabId)
    }

    private func ensureSelectedTab() {
        let activeTabs = settings.activeTabs
        guard !activeTabs.isEmpty else {
            selectedTabId = ""
            return
        }

        if !activeTabs.contains(where: { $0.id == selectedTabId }) {
            selectedTabId = activeTabs[0].id
        }
    }

    private func updateTransitionDirection(for newTabId: String) {
        let tabs = settings.activeTabs
        guard
            let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabId }),
            let nextIndex = tabs.firstIndex(where: { $0.id == newTabId })
        else {
            tabTransitionDirection = .trailing
            return
        }

        tabTransitionDirection = nextIndex > currentIndex ? .trailing : .leading
    }

    private func switchTab(direction: Int) {
        let tabs = settings.activeTabs
        guard !tabs.isEmpty,
              let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabId })
        else { return }

        let nextIndex = currentIndex + direction
        guard tabs.indices.contains(nextIndex) else { return }

        updateTransitionDirection(for: tabs[nextIndex].id)
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTabId = tabs[nextIndex].id
        }
    }
}