import SwiftUI

/// Drill-down from the "Unique Clients" stat card. Lists each client with
/// total + blocked query counts and last-seen time.
struct ClientsDrilldownView: View {
    let client: APIClient
    let range: TimeRange

    @State private var clients: [ClientSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && clients.isEmpty {
                LoadingView()
            } else if let err = errorMessage, clients.isEmpty {
                ErrorView(message: err) { Task { await load() } }
            } else if clients.isEmpty {
                ContentUnavailableView(
                    "No Clients",
                    systemImage: "desktopcomputer",
                    description: Text("No clients queried during this range.")
                )
            } else {
                List(clients) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.displayName).font(.headline)
                            Spacer()
                            Text(c.totalQueries.formatted())
                                .font(.subheadline).monospacedDigit()
                        }
                        HStack(spacing: 12) {
                            if !c.clientName.isEmpty && !c.clientIp.isEmpty {
                                Text(c.clientIp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Label("\(c.blockedQueries.formatted()) blocked", systemImage: "shield.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Text(c.lastSeenDate, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Unique Clients")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            clients = try await client.clients(range: range)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
