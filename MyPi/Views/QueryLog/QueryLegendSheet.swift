import SwiftUI

/// Reference sheet explaining each status icon shown in the Query Log.
struct QueryLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let description: String
    }

    private let entries: [Entry] = [
        .init(
            icon: "checkmark.circle.fill",
            color: .green,
            title: "Permitted",
            description: "Query was allowed and forwarded to the upstream resolver."
        ),
        .init(
            icon: "memorychip",
            color: .blue,
            title: "Cached",
            description: "Response served from Pi-hole's local cache — no upstream lookup."
        ),
        .init(
            icon: "shield.fill",
            color: .red,
            title: "Blocked",
            description: "Matched a blocklist (gravity, regex, or blacklist) and was blocked."
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: entry.icon)
                                .foregroundStyle(entry.color)
                                .font(.title3)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.headline)
                                Text(entry.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Status values are reported by Pi-hole v6. \"Blocked\" covers GRAVITY, REGEX, BLACKLIST and their CNAME variants.")
                }
            }
            .navigationTitle("Legend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
