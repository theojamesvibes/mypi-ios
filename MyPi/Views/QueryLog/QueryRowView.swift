import SwiftUI

struct QueryRowView: View {
    let query: QueryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: query.statusKind.systemImage)
                .foregroundStyle(query.statusKind.tint)
                .font(.body)
                .padding(.top, 3)
                .accessibilityLabel(query.statusKind.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(query.domain.isEmpty ? "(no domain)" : query.domain)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(query.clientDisplayName)
                        .lineLimit(1)
                    if let type = query.queryType, !type.isEmpty {
                        Text(type)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                    Spacer(minLength: 4)
                    Text(Self.timeText(query.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let instName = query.instanceName, !instName.isEmpty {
                    Text(instName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Time only for today's queries; the 48h / 7d / 30d ranges span several
    /// days, where a bare time would be ambiguous, so older rows add the date.
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .standard)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
