import SwiftUI
import Charts

/// Shared Dashboard chart: stacked bars per time bucket showing
/// Permitted (blue) and Blocked (red) query volume. Chart decorations are
/// stripped (no axes, legend, grid) so the shape itself carries the
/// information; a small footer restates the totals + percentages.
///
/// Used unmodified on both iPhone and iPad — pass a taller `height` on iPad.
struct QueryActivityChart: View {
    let history: HistoryResponse
    /// Full window being viewed — pinned as the chart's x-axis domain so the
    /// bar positions stay meaningful (and the card width stays constant) even
    /// when only a handful of buckets have data.
    var range: TimeRange
    var height: CGFloat = 80
    /// When set, the whole card is pinned to this height so two cards placed
    /// side-by-side on iPad match visually. Applied before `.background` so
    /// the background fills the pinned frame rather than the content's
    /// natural size.
    var cardHeight: CGFloat? = nil

    private var totals: (permitted: Int, blocked: Int) {
        history.buckets.reduce((0, 0)) { acc, b in
            (acc.0 + max(0, b.queries - b.blocked), acc.1 + b.blocked)
        }
    }

    private var total: Int { totals.permitted + totals.blocked }

    private var blockedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(totals.blocked) / Double(total)
    }

    private var permittedFraction: Double { 1 - blockedFraction }

    /// Bar slot width: plot width divided by bucket count, minus a small gap.
    private var barWidth: CGFloat {
        // Heuristic: for 48 buckets on a typical phone width (~340pt plot),
        // aim for roughly 5–6pt per bar. We set a fixed width independent of
        // the slot so Swift Charts never collapses bars to sub-pixel size.
        let count = history.buckets.count
        guard count > 0 else { return 3 }
        if count <= 24 { return 8 }
        if count <= 72 { return 4 }
        return 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Query Activity").font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Text(total.formatted(.number.notation(.compactName)))
                        .monospacedDigit()
                    Text("total").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Chart {
                ForEach(history.buckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.date),
                        y: .value("Permitted", max(0, bucket.queries - bucket.blocked)),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(Color.blue)

                    BarMark(
                        x: .value("Time", bucket.date),
                        y: .value("Blocked", bucket.blocked),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(Color.red)
                }
            }
            .chartXScale(domain: range.xDomain())
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: height)

            HStack(spacing: 20) {
                StatPip(
                    color: .blue,
                    percent: permittedFraction,
                    label: "Permitted",
                    count: totals.permitted
                )
                StatPip(
                    color: .red,
                    percent: blockedFraction,
                    label: "Blocked",
                    count: totals.blocked
                )
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity,
               minHeight: cardHeight,
               maxHeight: cardHeight,
               alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatPip: View {
    let color: Color
    let percent: Double
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(percent, format: .percent.precision(.fractionLength(1)))
                    .font(.subheadline).bold().monospacedDigit()
                Text("\(label) · \(count.formatted(.number.notation(.compactName)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
