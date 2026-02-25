import SwiftUI

struct PullRequestReviewPopover: View {
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
                CachedAsyncImage(url: url) { phase in
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
