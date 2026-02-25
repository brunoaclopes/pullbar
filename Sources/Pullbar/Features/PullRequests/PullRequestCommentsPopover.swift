import SwiftUI

struct PullRequestCommentsPopover: View {
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
