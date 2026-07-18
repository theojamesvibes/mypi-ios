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
                let maxCount = items.prefix(10).map(\.1).max() ?? 0
                ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { idx, item in
                    TopItemRow(
                        label: item.0,
                        count: item.1,
                        fraction: maxCount > 0 ? Double(item.1) / Double(maxCount) : 0,
                        color: color
                    )
                    if idx < min(items.count, 10) - 1 {
                        Divider().padding(.leading)
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Top-list row with a proportional tinted bar behind the text — reads as a
/// horizontal bar chart at zero extra height. `fraction` is the item's count
/// relative to the list's largest count (0…1). Shared by the iPhone sections
/// and the iPad `TopColumn`s.
struct TopItemRow: View {
    let label: String
    let count: Int
    let fraction: Double
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(count.formatted())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        // Behind the content, inside the card's horizontal padding, so the
        // bar aligns with the text rather than bleeding to the card edge.
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.14))
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .padding(.horizontal)
    }
}
