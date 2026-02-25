import SwiftUI

struct PullRequestChecksPopover: View {
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
