import SwiftUI

/// Row used in Query Log's "Unique Clients" mode. Displays one client with
/// total + blocked query counts and last-seen time.
struct ClientRowView: View {
    let client: ClientSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(client.displayName).font(.headline)
                Spacer()
                Text(client.totalQueries.formatted())
                    .font(.subheadline).monospacedDigit()
            }
            HStack(spacing: 12) {
                if !client.clientName.isEmpty && !client.clientIp.isEmpty {
                    Text(client.clientIp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("\(client.blockedQueries.formatted()) blocked", systemImage: "shield.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                if let lastSeen = client.lastSeen {
                    Text("last seen ") + Text(lastSeen, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
