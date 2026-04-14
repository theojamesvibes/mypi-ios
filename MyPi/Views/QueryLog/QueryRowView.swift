import SwiftUI

struct QueryRowView: View {
    let query: QueryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIndicator
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(query.domain)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(query.clientName ?? query.clientIp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(query.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let instName = query.instanceName {
                    Text(instName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIndicator: some View {
        let (color, icon): (Color, String) = {
            if query.isBlocked { return (.red, "shield.fill") }
            if query.isCached { return (.blue, "memorychip") }
            return (.green, "checkmark.circle.fill")
        }()
        return Image(systemName: icon)
            .foregroundStyle(color)
            .font(.body)
    }
}
