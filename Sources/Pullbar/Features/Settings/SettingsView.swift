import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: PullRequestStore

    @State private var tokenInput = ""
    @State private var tokenStatus = ""
    @State private var isImportingFromGHCLI = false
    @State private var ghProfiles: [GHCLIProfile] = []
    @State private var selectedGHProfileID: String = ""
    @State private var ghProfileStatus = ""
    @State private var isShowingHighRateWarning = false
    @State private var highRateWarningMessage = ""
    @State private var isEstimatingApplyCost = false

    private let keychain = KeychainService()
    private let ghCLIImporter = GHCLIImporter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCard("Authentication", caption: nil) {
                    authenticationSection
                }
                sectionCard("gh CLI profiles", caption: nil) {
                    ghProfilesSection
                }
                sectionCard(
                    "Tabs",
                    caption: "Enable/disable defaults and add fully custom tabs (max \(SettingsStore.maxTabs)).",
                    trailingCaption: "\(settings.tabs.count)/\(SettingsStore.maxTabs)"
                ) {
                    tabsSection
                }
                sectionCard("List", caption: nil) {
                    listSection
                }
                sectionCard("Refresh", caption: nil) {
                    refreshSection
                }
                sectionCard("Notification hint", caption: nil) {
                    notificationSection
                }
                sectionCard("App", caption: nil) {
                    appSection
                }
                sectionCard("Host", caption: "Advanced") {
                    hostSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .onAppear {
            refreshGHProfiles()
        }
        .onChange(of: selectedGHProfileID) { _, _ in
            switchToSelectedProfileIfNeeded()
        }
        .onChange(of: settings.prSortOrder) { _, _ in
            store.applySort(settings: settings)
            Task {
                await store.refreshAll(force: true, settings: settings)
            }
        }
        .alert("Review custom tab query", isPresented: $isShowingHighRateWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Apply anyway") {
                applyTabChangesNow()
            }
        } message: {
            Text(highRateWarningMessage)
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("GitHub Personal Access Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button("Save token") {
                    saveToken()
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Import from gh CLI") {
                    importFromGHCLI()
                }
                .disabled(isImportingFromGHCLI)

                Button("Remove token", role: .destructive) {
                    removeToken()
                }
            }
            if !tokenStatus.isEmpty {
                Text(tokenStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ghProfilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ghProfiles.isEmpty {
                Text("No authenticated gh profiles found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Profile", selection: $selectedGHProfileID) {
                    ForEach(ghProfiles) { profile in
                        Text("@\(profile.login) • \(profile.host)\(profile.active ? " (active)" : "")")
                            .tag(profile.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("Refresh profiles") {
                        refreshGHProfiles()
                    }
                }
            }

            if !ghProfileStatus.isEmpty {
                Text(ghProfileStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hostSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("GitHub host URL (empty = github.com)", text: $settings.enterpriseHostURL)
                .textFieldStyle(.roundedBorder)
            TextField("GitHub API URL (optional, e.g. https://api.github.com/graphql)", text: $settings.enterpriseAPIURL)
                .textFieldStyle(.roundedBorder)
            Text("GraphQL API endpoint: \(settings.resolvedGraphQLURL.absoluteString)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: $settings.refreshIntervalSeconds, in: 60...600, step: 10) {
                Text("Interval: \(settings.refreshIntervalSeconds)s")
            }
            Button("Refresh now") {
                Task {
                    await store.refreshAll(force: true, settings: settings)
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Order By", selection: $settings.prSortOrder) {
                ForEach(PRSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show PR author avatar", isOn: $settings.showAuthorAvatar)

            Text("Sort applies to all tabs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Text("Automatically start Pullbar when you sign in to macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let defaultTabs = settings.tabs.filter { $0.isDefault }
            let customTabs = settings.tabs.filter { !$0.isDefault }

            if !defaultTabs.isEmpty {
                Text("Default tabs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(defaultTabs) { tab in
                tabEditorCard {
                    Toggle(tab.title, isOn: tabEnabledBinding(tab.id))
                        .toggleStyle(.checkbox)

                    if let kind = tab.defaultKind {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base query")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(kind.defaultQuery)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Append filter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. team:mobile label:urgent", text: tabQueryBinding(tab.id), axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if !customTabs.isEmpty {
                Text("Custom tabs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            ForEach(customTabs) { tab in
                tabEditorCard {
                    HStack {
                        Toggle(tab.title, isOn: tabEnabledBinding(tab.id))
                            .toggleStyle(.checkbox)

                        Spacer()

                        Button("Remove", role: .destructive) {
                            settings.removeCustomTab(id: tab.id)
                            Task {
                                await store.refreshAll(force: true, settings: settings)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tab title")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Tab title", text: tabTitleBinding(tab.id))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Query")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Query (GitHub search syntax)", text: tabQueryBinding(tab.id), axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Picker("Match", selection: tabFilterMatchModeBinding(tab.id)) {
                                ForEach(PRTabFilterMatchMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        if tab.filters.isEmpty {
                            Text("No rules. This tab only uses the query above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(tab.filters) { filter in
                                    HStack(spacing: 8) {
                                        Picker("Field", selection: tabFilterFieldBinding(tab.id, filter.id)) {
                                            ForEach(PRTabFilterField.allCases) { field in
                                                Text(field.title).tag(field)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()

                                        Picker("Value", selection: tabFilterValueBinding(tab.id, filter.id)) {
                                            ForEach(filter.field.allowedValues) { value in
                                                Text(value.title).tag(value)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()

                                        Button(role: .destructive) {
                                            removeFilterRule(tabId: tab.id, filterId: filter.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Add rule") {
                                addFilterRule(tabId: tab.id)
                            }

                            Text("Rules are applied after fetching query results.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Add custom tab") {
                    settings.addCustomTab()
                }
                .disabled(settings.tabs.count >= SettingsStore.maxTabs)

                Button("Apply tab changes") {
                    applyTabChangesWithRateWarning()
                }
                .disabled(isEstimatingApplyCost)

                if isEstimatingApplyCost {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func applyTabChangesWithRateWarning() {
        guard !isEstimatingApplyCost else { return }

        let broadTabs = broadCustomTabsForWarning()

        isEstimatingApplyCost = true
        Task {
            defer { isEstimatingApplyCost = false }

            do {
                let assessment = try await store.assessRefreshCost(settings: settings)
                if assessment.shouldWarn || !broadTabs.isEmpty {
                    let heavyTabs = assessment.tabCosts
                        .filter { $0.cost >= 25 }
                        .map(\.title)

                    let tabSummary = heavyTabs.isEmpty
                        ? ""
                        : "\nHigh-cost tabs: \(heavyTabs.joined(separator: ", "))."

                    let broadSummary = broadTabs.isEmpty
                        ? ""
                        : "\nBroad-scope tabs: \(broadTabs.joined(separator: ", "))."

                    let severityPrefix: String
                    switch assessment.warningLevel {
                    case .high:
                        severityPrefix = "This apply is likely expensive."
                    case .moderate:
                        severityPrefix = "This apply may be expensive."
                    case .none:
                        severityPrefix = broadTabs.isEmpty ? "" : "This apply includes broad queries."
                    }

                    highRateWarningMessage = "\(severityPrefix) Estimated GraphQL cost is \(assessment.totalCost) points (remaining: \(assessment.remaining)/\(assessment.limit)). Review and narrow queries before applying.\(tabSummary)\(broadSummary)"
                    isShowingHighRateWarning = true
                    return
                }

                applyTabChangesNow()
            } catch {
                if !broadTabs.isEmpty {
                    highRateWarningMessage = "Could not estimate query cost right now, and these tabs appear broad: \(broadTabs.joined(separator: ", ")). Review and narrow queries before proceeding."
                    isShowingHighRateWarning = true
                } else {
                    highRateWarningMessage = "Could not estimate query cost right now. Applying may consume significant GraphQL points. Review your custom tab queries before proceeding."
                    isShowingHighRateWarning = true
                }
            }
        }
    }

    private func applyTabChangesNow() {
        Task {
            await store.refreshAll(force: true, settings: settings)
        }
    }

    private func broadCustomTabsForWarning() -> [String] {
        settings.activeTabs
            .filter { !$0.isDefault }
            .filter { isBroadQuery(settings.effectiveQuery(for: $0)) }
            .map(\.title)
    }

    private func isBroadQuery(_ query: String) -> Bool {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        if normalized == "is:pr archived:false" || normalized == "is:open is:pr archived:false" {
            return true
        }

        let hasPR = normalized.contains("is:pr")
        let hasScope = normalized.contains("repo:") || normalized.contains("org:") || normalized.contains("user:")
        let hasActor = normalized.contains("author:") || normalized.contains("assignee:") || normalized.contains("review-requested:") || normalized.contains("involves:")
        let hasNarrowing = normalized.contains("label:") || normalized.contains("base:") || normalized.contains("head:")

        if hasPR && !hasScope && !hasActor {
            return true
        }

        if hasPR && hasScope && !hasActor && !hasNarrowing {
            return true
        }

        return false
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include review requests", isOn: $settings.notifyReviewRequests)
            Toggle("Include open comments", isOn: $settings.notifyOpenComments)
            Toggle("Show numeric count in menu bar", isOn: $settings.showNotificationCount)
            Text("When disabled, the menu bar shows a subtle dot instead of a count.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tabEnabledBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.tabs.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == id }) else { return }
                tab.isEnabled = newValue
                settings.updateTab(tab)
            }
        )
    }

    private func tabTitleBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.tabs.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == id }) else { return }
                tab.title = newValue
                settings.updateTab(tab)
            }
        )
    }

    private func tabQueryBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { settings.tabs.first(where: { $0.id == id })?.query ?? "" },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == id }) else { return }
                tab.query = newValue
                settings.updateTab(tab)
            }
        )
    }

    private func tabFilterMatchModeBinding(_ id: String) -> Binding<PRTabFilterMatchMode> {
        Binding(
            get: { settings.tabs.first(where: { $0.id == id })?.filterMatchMode ?? .all },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == id }) else { return }
                tab.filterMatchMode = newValue
                settings.updateTab(tab)
            }
        )
    }

    private func tabFilterFieldBinding(_ tabId: String, _ filterId: String) -> Binding<PRTabFilterField> {
        Binding(
            get: {
                settings.tabs
                    .first(where: { $0.id == tabId })?
                    .filters
                    .first(where: { $0.id == filterId })?
                    .field ?? .unresolvedComments
            },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == tabId }) else { return }
                guard let index = tab.filters.firstIndex(where: { $0.id == filterId }) else { return }

                tab.filters[index].field = newValue
                if !newValue.allowedValues.contains(tab.filters[index].value),
                   let replacement = newValue.allowedValues.first {
                    tab.filters[index].value = replacement
                }

                settings.updateTab(tab)
            }
        )
    }

    private func tabFilterValueBinding(_ tabId: String, _ filterId: String) -> Binding<PRTabFilterValue> {
        Binding(
            get: {
                settings.tabs
                    .first(where: { $0.id == tabId })?
                    .filters
                    .first(where: { $0.id == filterId })?
                    .value ?? .hasUnresolvedComments
            },
            set: { newValue in
                guard var tab = settings.tabs.first(where: { $0.id == tabId }) else { return }
                guard let index = tab.filters.firstIndex(where: { $0.id == filterId }) else { return }

                tab.filters[index].value = newValue
                settings.updateTab(tab)
            }
        )
    }

    private func addFilterRule(tabId: String) {
        guard var tab = settings.tabs.first(where: { $0.id == tabId }) else { return }
        tab.filters.append(.default())
        settings.updateTab(tab)
    }

    private func removeFilterRule(tabId: String, filterId: String) {
        guard var tab = settings.tabs.first(where: { $0.id == tabId }) else { return }
        tab.filters.removeAll { $0.id == filterId }
        settings.updateTab(tab)
    }

    private func saveToken() {
        do {
            try keychain.saveToken(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
            tokenStatus = "Token saved securely in Keychain"
            tokenInput = ""
            Task {
                await store.refreshAll(force: true, settings: settings)
            }
        } catch {
            if case KeychainError.emptyToken = error {
                tokenStatus = "Token cannot be empty"
            } else {
                tokenStatus = "Unable to save token"
            }
        }
    }

    private func removeToken() {
        do {
            try keychain.deleteToken()
            tokenStatus = "Token removed"
        } catch {
            tokenStatus = "Unable to remove token"
        }
    }

    private func importFromGHCLI() {
        isImportingFromGHCLI = true
        tokenStatus = "Importing from gh CLI…"

        Task {
            do {
                let result = try ghCLIImporter.importActiveAuth()
                try applyImportedAuth(result)

                tokenStatus = "Imported from gh CLI for @\(result.login) on \(result.host)"
                await store.refreshAll(force: true, settings: settings)
                refreshGHProfiles()
            } catch {
                if let localized = error as? LocalizedError,
                   let message = localized.errorDescription,
                   !message.isEmpty {
                    tokenStatus = message
                } else {
                    tokenStatus = "Unable to import from gh CLI"
                }
            }

            isImportingFromGHCLI = false
        }
    }

    private var selectedProfile: GHCLIProfile? {
        ghProfiles.first(where: { $0.id == selectedGHProfileID })
    }

    private func refreshGHProfiles() {
        Task {
            do {
                let profiles = try ghCLIImporter.listProfiles()
                ghProfiles = profiles
                if selectedGHProfileID.isEmpty || !profiles.contains(where: { $0.id == selectedGHProfileID }) {
                    selectedGHProfileID = profiles.first(where: { $0.active })?.id ?? profiles.first?.id ?? ""
                }
                if let active = profiles.first(where: { $0.active }) {
                    ghProfileStatus = "Active gh profile: @\(active.login) on \(active.host)"
                } else {
                    ghProfileStatus = ""
                }
            } catch {
                ghProfiles = []
                selectedGHProfileID = ""
                if let localized = error as? LocalizedError,
                   let message = localized.errorDescription,
                   !message.isEmpty {
                    ghProfileStatus = message
                } else {
                    ghProfileStatus = "Unable to load gh profiles"
                }
            }
        }
    }

    private func switchToSelectedProfileIfNeeded() {
        guard let profile = selectedProfile else { return }

        if profile.active {
            return
        }

        isImportingFromGHCLI = true
        ghProfileStatus = "Switching gh profile to @\(profile.login) on \(profile.host)…"

        Task {
            do {
                try ghCLIImporter.switchActiveProfile(host: profile.host, login: profile.login)
                let result = try ghCLIImporter.importProfile(host: profile.host, login: profile.login)
                try applyImportedAuth(result)

                tokenStatus = "Imported from gh CLI for @\(result.login) on \(result.host)"
                ghProfileStatus = "Active gh profile: @\(result.login) on \(result.host)"

                await store.refreshAll(force: true, settings: settings)
                refreshGHProfiles()
            } catch {
                if let localized = error as? LocalizedError,
                   let message = localized.errorDescription,
                   !message.isEmpty {
                    ghProfileStatus = message
                } else {
                    ghProfileStatus = "Unable to switch gh profile"
                }
            }

            isImportingFromGHCLI = false
        }
    }

    private func applyImportedAuth(_ result: GHCLIImportResult) throws {
        try keychain.saveToken(result.token)

        if result.host == "github.com" {
            settings.enterpriseHostURL = ""
            settings.enterpriseAPIURL = ""
        } else {
            settings.enterpriseHostURL = result.host
            settings.enterpriseAPIURL = ""
        }
    }

    private func sectionCard<Content: View>(_ title: String, caption: String?, trailingCaption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            if caption != nil || trailingCaption != nil {
                HStack {
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let trailingCaption {
                        Text(trailingCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tabEditorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}