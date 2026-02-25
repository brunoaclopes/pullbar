import SwiftUI

struct PullRequestGroupSection: Identifiable {
    let key: String
    let items: [PullRequestItem]
    let subgroups: [PullRequestGroupSection]

    var id: String { key }

    var totalCount: Int {
        subgroups.isEmpty ? items.count : subgroups.reduce(0) { $0 + $1.totalCount }
    }
}

struct PullRequestGroupCard: View {
    let group: PullRequestGroupSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.key)
                    .font(.headline)

                Text("\(group.totalCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()
            }

            if group.subgroups.isEmpty {
                LazyVStack(spacing: 6) {
                    ForEach(group.items) { pr in
                        PullRequestRow(pr: pr)
                    }
                }
            } else {
                PullRequestSubGroupView(subgroups: group.subgroups)
            }
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
}

struct PullRequestSubGroupView: View {
    let subgroups: [PullRequestGroupSection]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(subgroups) { sub in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(sub.key)
                            .font(.subheadline.weight(.semibold))

                        Text("\(sub.totalCount)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(Capsule())

                        Spacer()
                    }

                    if sub.subgroups.isEmpty {
                        LazyVStack(spacing: 6) {
                            ForEach(sub.items) { pr in
                                PullRequestRow(pr: pr, nesting: 1)
                            }
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(sub.subgroups) { leaf in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(Color.primary.opacity(0.2))
                                            .frame(width: 3, height: 12)
                                        Text(leaf.key)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text("\(leaf.totalCount)")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.primary.opacity(0.07))
                                            .clipShape(Capsule())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    LazyVStack(spacing: 6) {
                                        ForEach(leaf.items) { pr in
                                            PullRequestRow(pr: pr, nesting: 2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
