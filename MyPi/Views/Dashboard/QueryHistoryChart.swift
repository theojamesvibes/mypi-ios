import SwiftUI
import Charts

struct QueryHistoryChart: View {
    let history: HistoryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query History")
                .font(.headline)

            Chart {
                ForEach(history.buckets) { bucket in
                    AreaMark(
                        x: .value("Time", bucket.date),
                        y: .value("Queries", bucket.queries)
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", bucket.date),
                        y: .value("Queries", bucket.queries)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", bucket.date),
                        y: .value("Blocked", bucket.blocked)
                    )
                    .foregroundStyle(.red.opacity(0.3))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", bucket.date),
                        y: .value("Blocked", bucket.blocked)
                    )
                    .foregroundStyle(.red)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading) {
                HStack(spacing: 16) {
                    Label("Total", systemImage: "circle.fill").foregroundStyle(.blue)
                    Label("Blocked", systemImage: "circle.fill").foregroundStyle(.red)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
