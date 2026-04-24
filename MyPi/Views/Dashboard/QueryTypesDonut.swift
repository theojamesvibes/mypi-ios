import SwiftUI
import Charts

/// Donut breakdown of query dispositions — mirrors the "Query Types" card
/// on the MyPi web dashboard.
struct QueryTypesDonut: View {
    let stats: SummaryStats
    /// Optional fixed card height so this view matches siblings placed
    /// side-by-side on iPad. Applied before `.background` so the background
    /// fills the pinned frame.
    var cardHeight: CGFloat? = nil

    private struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private var slices: [Slice] {
        let forwarded = stats.queriesForwarded
        let cached = stats.queriesCached
        let blocked = stats.queriesBlocked
        let other = max(0, stats.dnsQueriesToday - forwarded - cached - blocked)
        return [
            .init(label: "Forwarded", count: forwarded, color: .green),
            .init(label: "Cached", count: cached, color: .teal),
            .init(label: "Blocked", count: blocked, color: .red),
            .init(label: "Other", count: other, color: .gray),
        ].filter { $0.count > 0 }
    }

    private var total: Int {
        slices.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Query Types")
                .font(.headline)

            HStack(alignment: .center, spacing: 16) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Count", slice.count),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
                .frame(width: 140, height: 140)

                // Two-column Grid so labels and percents line up vertically
                // without fighting over `Spacer()` width. The plain HStack
                // version wrapped "Forwarded", "Cached", and "Blocked" onto
                // two lines once the percent text took its slot — the
                // fixed-width iPad card left ~130pt for the legend column
                // and a caption-sized "Forwarded" + "43.3%" combo didn't
                // fit. `.lineLimit(1)` + `.minimumScaleFactor(0.85)` on the
                // label keeps it single-line in the worst case without
                // truncating visibly.
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(slices) { slice in
                        GridRow {
                            HStack(spacing: 8) {
                                Circle().fill(slice.color).frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            Text(percent(for: slice))
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity,
               minHeight: cardHeight,
               maxHeight: cardHeight,
               alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func percent(for slice: Slice) -> String {
        guard total > 0 else { return "—" }
        let p = Double(slice.count) / Double(total)
        return p.formatted(.percent.precision(.fractionLength(1)))
    }
}
