import SwiftUI

struct TopListsView: View {
    let top: TopStatsResponse

    var body: some View {
        VStack(spacing: 12) {
            TopListSection(
                title: "Top Blocked Domains",
                icon: "shield.slash",
                color: .red,
                items: top.topBlocked.map { ($0.domain, $0.count) }
            )
            TopListSection(
                title: "Top Permitted Domains",
                icon: "checkmark.circle",
                color: .green,
                items: top.topPermitted.map { ($0.domain, $0.count) }
            )
            TopListSection(
                title: "Top Clients",
                icon: "desktopcomputer",
                color: .purple,
                items: top.topClients.map { ($0.client, $0.count) }
            )
        }
        .padding(.horizontal)
    }
}

private struct TopListSection: View {
    let title: String
    let icon: String
    let color: Color
    let items: [(String, Int)]

    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { idx, item in
                    HStack {
                        Text(item.0)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(item.1.formatted())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    if idx < min(items.count, 10) - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
