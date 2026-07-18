import SwiftUI
import Charts

/// Shared Dashboard chart card with three modes:
///  - **All** — stacked bars of Permitted (blue) / Blocked (red) per bucket.
///  - **Blocked %** — line of the blocked share per bucket, derived locally
///    from the same history buckets (no extra requests).
///  - **By Device** — bars stacked per Pi-hole instance, colored with each
///    device's server-assigned color. Only offered when the server has more
///    than one device; the per-device series are fetched on demand by
///    `DashboardViewModel`.
///
/// All modes share sparse, recessive axes and drag/tap scrubbing with a
/// snap-to-bucket annotation. Used unmodified on iPhone and iPad — pass a
/// taller `height` on iPad.
struct QueryActivityChart: View {
    @Bindable var vm: DashboardViewModel
    let history: HistoryResponse
    /// Full window being viewed — pinned as the chart's x-axis domain so the
    /// bar positions stay meaningful (and the card width stays constant) even
    /// when only a handful of buckets have data.
    var range: TimeRange
    var height: CGFloat = 160
    /// When set, the whole card is pinned to this height so two cards placed
    /// side-by-side on iPad match visually. Applied before `.background` so
    /// the background fills the pinned frame rather than the content's
    /// natural size.
    var cardHeight: CGFloat? = nil

    /// Raw scrub position from `.chartXSelection`; snapped to the nearest
    /// bucket for the annotation.
    @State private var rawSelection: Date?

    // MARK: - Derived

    private var totals: (permitted: Int, blocked: Int) {
        HistoryMath.totals(history.buckets)
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

    private var blockedPercentSeries: [(date: Date, percent: Double)] {
        HistoryMath.blockedPercentSeries(history.buckets)
    }

    /// Y ceiling for the Blocked % mode: headroom above the peak so the line
    /// sits in the plot, floored at 5 so a flat low percentage doesn't render
    /// as a dramatic full-height wall.
    private var percentDomainMax: Double {
        let peak = blockedPercentSeries.map(\.percent).max() ?? 0
        return min(100, max(5, (peak * 1.25).rounded(.up)))
    }

    /// Number of devices the server reports — gates the By Device segment.
    private var deviceCount: Int {
        (vm.summary?.instances.filter(\.isActive).count) ?? 0
    }

    /// Fixed fallback order for devices whose server color is missing or
    /// unparsable — assigned by stable instance order, never re-cycled when
    /// the list changes size.
    private static let fallbackPalette: [Color] = [.blue, .orange, .purple, .teal, .indigo, .pink]

    private func deviceColor(_ ih: InstanceHistory, index: Int) -> Color {
        ih.instance.color.flatMap { Color(hex: $0) }
            ?? Self.fallbackPalette[index % Self.fallbackPalette.count]
    }

    private var selectedBucket: HistoryBucket? {
        guard let rawSelection else { return nil }
        return HistoryMath.nearestBucket(in: history.buckets, to: rawSelection)
    }

    /// Sparse x labels: hour-of-day up to 48h, month+day for 7d/30d.
    private var xLabelFormat: Date.FormatStyle {
        switch range {
        case .days7, .days30:
            return .dateTime.month(.abbreviated).day()
        default:
            return .dateTime.hour()
        }
    }

    /// Scrub-annotation timestamp: include the day once buckets span days.
    private func annotationTime(_ date: Date) -> String {
        switch range {
        case .days7, .days30:
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        default:
            return date.formatted(.dateTime.hour().minute())
        }
    }

    // MARK: - Body

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

            Picker("Chart mode", selection: $vm.activityMode) {
                Text(ActivityChartMode.all.label).tag(ActivityChartMode.all)
                Text(ActivityChartMode.blockedPercent.label).tag(ActivityChartMode.blockedPercent)
                if deviceCount > 1 {
                    Text(ActivityChartMode.byDevice.label).tag(ActivityChartMode.byDevice)
                }
            }
            .pickerStyle(.segmented)

            chart
                .frame(height: height)

            footer
        }
        .padding()
        .frame(maxWidth: .infinity,
               minHeight: cardHeight,
               maxHeight: cardHeight,
               alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        switch vm.activityMode {
        case .all:
            allChart
        case .blockedPercent:
            percentChart
        case .byDevice:
            if vm.instanceHistories.isEmpty {
                // Per-device series still loading (or all fetches failed) —
                // keep showing the total so the card never goes blank.
                allChart.overlay { ProgressView() }
            } else {
                deviceChart
            }
        }
    }

    private var allChart: some View {
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
            scrubMark
        }
        .chartXScale(domain: range.xDomain())
        .chartPlotStyle { $0.clipped() }
        .chartXSelection(value: $rawSelection)
        .chartXAxis { xAxisMarks }
        .chartYAxis { countYAxisMarks }
    }

    private var percentChart: some View {
        Chart {
            ForEach(blockedPercentSeries, id: \.date) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Blocked %", point.percent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.red.opacity(0.18), Color.red.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Blocked %", point.percent)
                )
                .foregroundStyle(Color.red)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            scrubMark
        }
        .chartXScale(domain: range.xDomain())
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: 0...percentDomainMax)
        .chartXSelection(value: $rawSelection)
        .chartXAxis { xAxisMarks }
        .chartYAxis { percentYAxisMarks }
    }

    private var deviceChart: some View {
        Chart {
            ForEach(vm.instanceHistories) { ih in
                ForEach(ih.history.buckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.date),
                        y: .value("Queries", bucket.queries),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(by: .value("Device", ih.instance.name))
                }
            }
            scrubMark
        }
        .chartForegroundStyleScale(
            domain: vm.instanceHistories.map(\.instance.name),
            range: vm.instanceHistories.enumerated().map { deviceColor($1, index: $0) }
        )
        .chartLegend(.hidden)  // custom Grid legend in the footer
        .chartXScale(domain: range.xDomain())
        .chartPlotStyle { $0.clipped() }
        .chartXSelection(value: $rawSelection)
        .chartXAxis { xAxisMarks }
        .chartYAxis { countYAxisMarks }
    }

    /// Scrub rule + annotation, shared by all modes.
    @ChartContentBuilder
    private var scrubMark: some ChartContent {
        if let bucket = selectedBucket {
            RuleMark(x: .value("Selected", bucket.date))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(
                    position: .top, spacing: 4,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    annotationCard(for: bucket)
                }
        }
    }

    @ViewBuilder
    private func annotationCard(for bucket: HistoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(annotationTime(bucket.date))
                .font(.caption2.bold())

            switch vm.activityMode {
            case .all, .blockedPercent:
                let permitted = max(0, bucket.queries - bucket.blocked)
                let pct = bucket.queries > 0
                    ? Double(bucket.blocked) / Double(bucket.queries) : 0
                annotationRow(color: .blue, label: "Permitted",
                              value: permitted.formatted(.number.notation(.compactName)))
                annotationRow(color: .red, label: "Blocked",
                              value: "\(bucket.blocked.formatted(.number.notation(.compactName))) (\(pct.formatted(.percent.precision(.fractionLength(1)))))")
            case .byDevice:
                ForEach(Array(vm.instanceHistories.enumerated()), id: \.element.id) { idx, ih in
                    let count = HistoryMath.nearestBucket(in: ih.history.buckets, to: bucket.date)?.queries ?? 0
                    annotationRow(color: deviceColor(ih, index: idx),
                                  label: ih.instance.name,
                                  value: count.formatted(.number.notation(.compactName)))
                }
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    private func annotationRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2).monospacedDigit()
        }
    }

    // MARK: - Axes

    private var xAxisMarks: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine().foregroundStyle(.quaternary)
            AxisValueLabel(format: xLabelFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var countYAxisMarks: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(.quaternary)
            AxisValueLabel {
                if let n = value.as(Int.self) {
                    Text(n.formatted(.number.notation(.compactName)))
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var percentYAxisMarks: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(.quaternary)
            AxisValueLabel {
                if let n = value.as(Double.self) {
                    Text("\(Int(n))%")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch vm.activityMode {
        case .all, .blockedPercent:
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
        case .byDevice:
            // Same two-column Grid legend convention as QueryTypesDonut.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(Array(vm.instanceHistories.enumerated()), id: \.element.id) { idx, ih in
                    let deviceTotal = ih.history.buckets.reduce(0) { $0 + $1.queries }
                    GridRow {
                        HStack(spacing: 8) {
                            Circle().fill(deviceColor(ih, index: idx))
                                .frame(width: 8, height: 8)
                            Text(ih.instance.name)
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(deviceTotal.formatted(.number.notation(.compactName)))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
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
