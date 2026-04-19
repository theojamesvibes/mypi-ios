import SwiftUI

/// Drill-down from the "Blocked" stat card. Shows one row per blocked domain,
/// with the most recent block time. Latest-per-domain is computed client-side
/// by walking the blocked-only query feed (already sorted timestamp DESC) and
/// keeping the first occurrence of each domain. One network call, bounded to
/// `page_size=500` rows.
struct BlockedDrilldownView: View {
    let client: APIClient
    let range: TimeRange

    struct DomainBlock: Identifiable {
        let domain: String
        let latest: Date
        let latestStatus: String
        let occurrences: Int
        var id: String { domain }
    }

    @State private var rows: [DomainBlock] = []
    @State private var scannedCount: Int = 0
    @State private var truncated: Bool = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && rows.isEmpty {
                LoadingView()
            } else if let err = errorMessage, rows.isEmpty {
                ErrorView(message: err) { Task { await load() } }
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "Nothing Blocked",
                    systemImage: "shield.slash",
                    description: Text("No blocked queries in this range.")
                )
            } else {
                List {
                    Section {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.domain)
                                    .font(.subheadline).bold()
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text(row.latestStatus)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.red.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.red)
                                    if row.occurrences > 1 {
                                        Text("\(row.occurrences.formatted())×")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(row.latest, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } footer: {
                        if truncated {
                            Text("Showing distinct domains from the most recent \(scannedCount.formatted()) blocked queries in this range.")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Blocked Domains")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await client.blockedQueries(range: range)
            var seen: [String: DomainBlock] = [:]
            for item in page.items {
                if let existing = seen[item.domain] {
                    seen[item.domain] = DomainBlock(
                        domain: existing.domain,
                        latest: existing.latest,
                        latestStatus: existing.latestStatus,
                        occurrences: existing.occurrences + 1
                    )
                } else {
                    seen[item.domain] = DomainBlock(
                        domain: item.domain,
                        latest: item.date,
                        latestStatus: item.status,
                        occurrences: 1
                    )
                }
            }
            rows = seen.values.sorted { $0.latest > $1.latest }
            scannedCount = page.items.count
            truncated = page.items.count >= page.pageSize && page.total > page.items.count
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
