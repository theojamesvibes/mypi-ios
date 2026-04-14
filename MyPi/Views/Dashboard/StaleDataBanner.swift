import SwiftUI

struct StaleDataBanner: View {
    let lastUpdated: Date
    /// If true the banner turns red (past the 2-sync threshold).
    var critical: Bool = true

    var body: some View {
        HStack {
            Image(systemName: critical ? "exclamationmark.triangle.fill" : "clock")
                .foregroundStyle(critical ? .red : .orange)
            Text("Showing cached data · Last updated \(lastUpdated, style: .relative) ago")
                .font(.footnote)
                .foregroundStyle(critical ? .red : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            (critical ? Color.red : Color.orange).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal)
    }
}
