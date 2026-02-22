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
                        await store.refreshAll(force: true, settings: settings)
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
                            await store.refreshAll(force: true, settings: settings)
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
                        await store.refreshAll(force: true, settings: settings)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if selectedTabItems.isEmpty {
            emptyTabState
        } else {
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
                            await store.refreshAll(force: true, settings: settings)
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
}

private struct PullRequestRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: PullRequestStore

    let pr: PullRequestItem
    @State private var isHovering = false
    @State private var isHoveringReviewTag = false
    @State private var isShowingReviewPopover = false
    @State private var isHoveringChecksTag = false
    @State private var isShowingChecksPopover = false
    @State private var isHoveringCommentsTag = false
    @State private var isShowingCommentsPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(pr.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Spacer()

                Text(pr.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(pr.repository)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 5) {
                        if settings.showAuthorAvatar {
                            authorAvatar
                        }

                        Text("@\(pr.author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(alignment: .center, spacing: 8) {
                    Button {
                        if isShowingReviewPopover {
                            isShowingReviewPopover = false
                        } else {
                            Task {
                                await store.ensureReviewDetailsLoaded(for: pr, settings: settings)
                                isShowingReviewPopover = true
                            }
                        }
                    } label: {
                        metaStatus(icon: "checkmark.seal", text: pr.reviewSummary.text, tint: reviewTint)
                            .background(
                                Capsule()
                                    .fill(reviewTint.opacity(isHoveringReviewTag ? 0.08 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringReviewTag = hovering
                    }
                    .popover(isPresented: $isShowingReviewPopover, arrowEdge: .bottom) {
                        PullRequestReviewPopover(pr: pr)
                    }
                    .help("Show review details")
                    .animation(.easeInOut(duration: 0.2), value: isHoveringReviewTag)

                    Button {
                        if isShowingChecksPopover {
                            isShowingChecksPopover = false
                        } else {
                            Task {
                                await store.ensureChecksDetailsLoaded(for: pr, settings: settings)
                                isShowingChecksPopover = true
                            }
                        }
                    } label: {
                        metaStatus(icon: "checklist", text: pr.checkSummary.text, tint: checkTint)
                            .background(
                                Capsule()
                                    .fill(checkTint.opacity(isHoveringChecksTag ? 0.08 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringChecksTag = hovering
                    }
                    .popover(isPresented: $isShowingChecksPopover, arrowEdge: .bottom) {
                        PullRequestChecksPopover(pr: pr)
                    }
                    .help("Show checks details")

                    if pr.reviewThreadsTotal > 0 {
                        Button {
                            if isShowingCommentsPopover {
                                isShowingCommentsPopover = false
                            } else {
                                Task {
                                    await store.ensureCommentDetailsLoaded(for: pr, settings: settings)
                                    isShowingCommentsPopover = true
                                }
                            }
                        } label: {
                            metaStatus(
                                icon: "text.bubble",
                                text: pr.unresolvedReviewThreads > 0
                                    ? "Comments \(pr.unresolvedReviewThreads)"
                                    : "Comments",
                                tint: threadTint
                            )
                            .background(
                                Capsule()
                                    .fill(threadTint.opacity(isHoveringCommentsTag ? 0.08 : 0))
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isHoveringCommentsTag = hovering
                        }
                        .popover(isPresented: $isShowingCommentsPopover, arrowEdge: .bottom) {
                            PullRequestCommentsPopover(pr: pr)
                        }
                        .help("Show comments details")
                        .animation(.easeInOut(duration: 0.2), value: isHoveringCommentsTag)
                    }

                    Spacer()

                    changeCountIndicator
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(reviewAccentColor)
                .frame(width: 5)
                .padding(.vertical, 6)
                .opacity(reviewAccentOpacity)
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            NSWorkspace.shared.open(pr.url)
        }
    }

    private var reviewAccentColor: Color {
        switch pr.reviewSummary {
        case .approved:
            return .green
        case .changesRequested:
            return .orange
        case .reviewRequired, .none:
            return .clear
        }
    }

    private var reviewAccentOpacity: Double {
        switch pr.reviewSummary {
        case .approved, .changesRequested:
            return 1
        case .reviewRequired, .none:
            return 0
        }
    }

    private var reviewTint: Color {
        switch pr.reviewSummary {
        case .approved:
            return .green
        case .changesRequested:
            return .orange
        case .reviewRequired:
            return .blue
        case .none:
            return .secondary
        }
    }

    private var checkTint: Color {
        switch pr.checkSummary {
        case .passing:
            return .green
        case .failing:
            return .red
        case .pending:
            return .yellow
        case .none:
            return .secondary
        }
    }

    private var threadTint: Color {
        pr.unresolvedReviewThreads > 0 ? .orange : .secondary
    }

    private var changeCountIndicator: some View {
        Button {
            NSWorkspace.shared.open(pr.filesURL)
        } label: {
            HStack(spacing: 8) {
                Text("+\(pr.additions)")
                    .foregroundStyle(.green)
                Text("-\(pr.deletions)")
                    .foregroundStyle(.red)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .opacity(isHovering ? 1 : 0.75)
        }
        .buttonStyle(.plain)
        .help("Open changed files")
    }

    private var authorAvatar: some View {
        Group {
            if let avatarURL = pr.authorAvatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
        .clipShape(Circle())
    }

    private var borderColor: Color {
        if reviewAccentOpacity > 0 {
            return reviewAccentColor.opacity(isHovering ? 0.6 : 0.35)
        }

        return Color.primary.opacity(isHovering ? 0.18 : 0.08)
    }

    private func metaStatus(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .foregroundStyle(tint)
    }
}

private struct PullRequestReviewPopover: View {
    let pr: PullRequestItem
    @State private var isHoveringOpenReviewLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review")
                .font(.subheadline.weight(.semibold))

            if pr.reviewDetails.approvedBy.isEmpty,
               pr.reviewDetails.changesRequestedBy.isEmpty,
               pr.reviewDetails.reviewRequestedFrom.isEmpty {
                Text("No detailed review actors available for this pull request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !pr.reviewDetails.approvedBy.isEmpty {
                        reviewSection(
                            title: "Approved by",
                            icon: "checkmark.circle.fill",
                            tint: .green,
                            names: pr.reviewDetails.approvedBy
                        )
                    }

                    if !pr.reviewDetails.changesRequestedBy.isEmpty {
                        reviewSection(
                            title: "Changes requested by",
                            icon: "exclamationmark.circle.fill",
                            tint: .orange,
                            names: pr.reviewDetails.changesRequestedBy
                        )
                    }

                    if !pr.reviewDetails.reviewRequestedFrom.isEmpty {
                        reviewSection(
                            title: "Review requested from",
                            icon: "person.crop.circle.badge.questionmark",
                            tint: .blue,
                            names: pr.reviewDetails.reviewRequestedFrom
                        )
                    }
                }
            }

            Divider()

            Text("Open review in GitHub")
                .font(.subheadline)
                .foregroundStyle(isHoveringOpenReviewLink ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringOpenReviewLink = hovering
                }
                .onTapGesture {
                    NSWorkspace.shared.open(pr.url)
                }
                .help("Open review in GitHub")
                .animation(.easeInOut(duration: 0.16), value: isHoveringOpenReviewLink)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }

    private func reviewSection(title: String, icon: String, tint: Color, names: [PullRequestReviewActor]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 6) {
                        avatarView(for: name, fallbackIcon: icon, tint: tint)
                        Text(name.login)
                            .font(.caption)
                    }
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func avatarView(for actor: PullRequestReviewActor, fallbackIcon: String, tint: Color) -> some View {
        Group {
            if let url = actor.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: fallbackIcon)
                            .foregroundStyle(tint)
                    }
                }
            } else {
                Image(systemName: fallbackIcon)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(Circle())
    }
}

private struct PullRequestCommentsPopover: View {
    let pr: PullRequestItem
    @State private var isHoveringOpenCommentsLink = false
    @State private var hoveringThreadId: String?

    private var unresolvedCount: Int {
        pr.commentThreads.reduce(0) { count, thread in
            count + (thread.status == .unresolved ? 1 : 0)
        }
    }

    private var sortedThreads: [PullRequestCommentThread] {
        pr.commentThreads.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .unresolved
            }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Comments")
                    .font(.subheadline.weight(.semibold))

                if unresolvedCount > 0 {
                    Text("• \(unresolvedCount) unresolved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if sortedThreads.isEmpty {
                Text("No comment threads reported for this pull request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedThreads) { thread in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: thread.status == .unresolved ? "text.bubble.fill" : "checkmark.bubble")
                                    .foregroundStyle(thread.status == .unresolved ? Color.orange : Color.green)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(thread.preview)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(threadTitleColor(for: thread))

                                    HStack(spacing: 6) {
                                        Text(thread.status.text)
                                        if let author = thread.author {
                                            Text("•")
                                            Text("@\(author)")
                                        }
                                        if thread.isOutdated {
                                            Text("•")
                                            Text("Outdated")
                                        }
                                        if let path = thread.path {
                                            Text("•")
                                            Text(path)
                                                .lineLimit(1)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 6)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(threadRowHoverBackground(for: thread))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    hoveringThreadId = thread.id
                                } else if hoveringThreadId == thread.id {
                                    hoveringThreadId = nil
                                }
                            }
                            .onTapGesture {
                                openThread(thread)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            Text("Open conversation in GitHub")
                .font(.subheadline)
                .foregroundStyle(isHoveringOpenCommentsLink ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringOpenCommentsLink = hovering
                }
                .onTapGesture {
                    NSWorkspace.shared.open(pr.url)
                }
                .help("Open conversation in GitHub")
                .animation(.easeInOut(duration: 0.16), value: isHoveringOpenCommentsLink)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private func openThread(_ thread: PullRequestCommentThread) {
        if let url = thread.url {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(pr.url)
    }

    private func threadTitleColor(for thread: PullRequestCommentThread) -> Color {
        guard thread.url != nil else {
            return .primary
        }

        return hoveringThreadId == thread.id ? Color.primary.opacity(0.95) : Color.primary.opacity(0.88)
    }

    private func threadRowHoverBackground(for thread: PullRequestCommentThread) -> Color {
        guard thread.url != nil, hoveringThreadId == thread.id else {
            return .clear
        }

        return Color.primary.opacity(0.06)
    }
}

private struct PullRequestChecksPopover: View {
    let pr: PullRequestItem
    @State private var isHoveringOpenChecksLink = false
    @State private var hoveringCheckId: String?

    private var groupedChecks: [(category: String, checks: [PullRequestCheck])] {
        let groups = Dictionary(grouping: pr.checks) { $0.category }
        return groups
            .map { category, checks in
                (category, checks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
            .sorted { $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Checks")
                .font(.subheadline.weight(.semibold))

            if groupedChecks.isEmpty {
                Text("No checks reported for this pull request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedChecks, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(group.checks) { check in
                                        HStack(spacing: 8) {
                                            Image(systemName: icon(for: check.status))
                                                .foregroundStyle(color(for: check.status))
                                            Text(check.name)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .foregroundStyle(checkTitleColor(for: check))
                                            Spacer(minLength: 8)
                                            Text(check.status.text)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(checkRowHoverBackground(for: check))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            if hovering {
                                                hoveringCheckId = check.id
                                            } else if hoveringCheckId == check.id {
                                                hoveringCheckId = nil
                                            }
                                        }
                                        .onTapGesture {
                                            openCheck(check)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            Text("Open checks in GitHub")
                .font(.subheadline)
                .foregroundStyle(isHoveringOpenChecksLink ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringOpenChecksLink = hovering
                }
                .onTapGesture {
                    NSWorkspace.shared.open(pr.checksURL)
                }
                .help("Open checks in GitHub")
                .animation(.easeInOut(duration: 0.16), value: isHoveringOpenChecksLink)
        }
        .padding(12)
        .frame(width: 290, alignment: .leading)
    }

    private func icon(for status: PullRequestCheckStatus) -> String {
        switch status {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        case .pending:
            return "clock.fill"
        }
    }

    private func color(for status: PullRequestCheckStatus) -> Color {
        switch status {
        case .success:
            return .green
        case .failure:
            return .red
        case .pending:
            return .orange
        }
    }

    private func openCheck(_ check: PullRequestCheck) {
        if let url = check.url {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(pr.checksURL)
    }

    private func checkTitleColor(for check: PullRequestCheck) -> Color {
        guard check.url != nil else {
            return .primary
        }

        return hoveringCheckId == check.id ? Color.primary.opacity(0.95) : Color.primary.opacity(0.88)
    }

    private func checkRowHoverBackground(for check: PullRequestCheck) -> Color {
        guard check.url != nil, hoveringCheckId == check.id else {
            return .clear
        }

        return Color.primary.opacity(0.06)
    }
}