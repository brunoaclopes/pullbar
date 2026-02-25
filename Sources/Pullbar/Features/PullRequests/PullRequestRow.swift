import SwiftUI

struct PullRequestRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: PullRequestStore

    let pr: PullRequestItem
    var nesting: Int = 0
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
                HStack(spacing: 6) {
                    Text(settings.showPRNumber ? "#\(pr.number) \(pr.title)" : pr.title)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(pr.isDraft ? .secondary : .primary)

                    if pr.isDraft {
                        Text("Draft")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.14))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

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
                .fill(Color.primary.opacity(isHovering ? rowHoverFill : rowRestFill))
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

    private var rowRestFill: Double {
        switch nesting {
        case 0:  return 0.03
        default: return 0.07
        }
    }

    private var rowHoverFill: Double {
        switch nesting {
        case 0:  return 0.08
        default: return 0.12
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
