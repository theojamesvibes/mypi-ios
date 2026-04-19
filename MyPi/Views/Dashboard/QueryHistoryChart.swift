import SwiftUI

/// Shows the proportion of permitted vs blocked queries as a single,
/// full-width horizontal bar — intentionally simple so it reads at a
/// glance on a phone. Absolute volume over time is de-emphasised;
/// what matters here is "what fraction of DNS traffic got blocked".
struct QueryHistoryChart: View {
    let history: HistoryResponse

    private var totals: (permitted: Int, blocked: Int) {
        let p = history.buckets.reduce(0) { $0 + max(0, $1.queries - $1.blocked) }
        let b = history.buckets.reduce(0) { $0 + $1.blocked }
        return (p, b)
    }

    private var total: Int { totals.permitted + totals.blocked }

    private var blockedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(totals.blocked) / Double(total)
    }

    private var permittedFraction: Double { 1 - blockedFraction }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Query Composition")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text(total.formatted()).monospacedDigit()
                    Text("total").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            ProportionBar(
                segments: [
                    .init(fraction: permittedFraction, color: .blue),
                    .init(fraction: blockedFraction, color: .red),
                ]
            )
            .frame(height: 16)

            HStack(spacing: 20) {
                LegendItem(
                    color: .blue,
                    label: "Permitted",
                    value: totals.permitted,
                    fraction: permittedFraction
                )
                LegendItem(
                    color: .red,
                    label: "Blocked",
                    value: totals.blocked,
                    fraction: blockedFraction
                )
                Spacer()
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ProportionBar: View {
    struct Segment: Hashable {
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments, id: \.self) { segment in
                    segment.color
                        .frame(width: max(0, geo.size.width * segment.fraction))
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(fraction, format: .percent.precision(.fractionLength(1)))
                    .font(.subheadline).bold().monospacedDigit()
                Text("\(label) · \(value.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
