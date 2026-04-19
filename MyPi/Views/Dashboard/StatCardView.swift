import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var showsDisclosure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.title3).bold()
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
