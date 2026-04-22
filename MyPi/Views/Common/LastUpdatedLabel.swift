import SwiftUI

/// Always-visible freshness indicator shown at the top of Dashboard and
/// Query Log. Separate from `StaleDataBanner` — that one only appears when
/// the data is past the stale threshold and turns red; this one is the
/// neutral "when was this last refreshed" label.
struct LastUpdatedLabel: View {
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Group {
                if let lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                } else {
                    Text("Not yet updated")
                }
            }
            .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
