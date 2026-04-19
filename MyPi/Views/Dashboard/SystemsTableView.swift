import SwiftUI

struct SystemsTableView: View {
    let instances: [InstanceSummary]
    var syncStatus: SyncStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pi-hole Instances")
                .font(.headline)
                .padding(.horizontal)

            if instances.isEmpty {
                Text("No instances available")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(instances.enumerated()), id: \.element.id) { idx, instance in
                        InstanceRow(
                            instance: instance,
                            syncResult: syncStatus?.results.first(where: { $0.name == instance.name }),
                            lastSyncAt: syncStatus?.completedAt
                        )
                        if idx < instances.count - 1 {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
}

private struct InstanceRow: View {
    let instance: InstanceSummary
    let syncResult: InstanceSyncResult?
    let lastSyncAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusDot
                Text(instance.name)
                    .font(.subheadline).bold()
                if instance.isMaster {
                    Text("master")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue, in: Capsule())
                }
                Spacer()
                Text(instance.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Metric(label: "Queries", value: instance.dnsQueriesToday.formatted())
                Metric(label: "Blocked", value: instance.queriesBlocked.formatted())
                Metric(label: "%", value: String(format: "%.1f%%", instance.percentBlocked))
                Metric(label: "Clients", value: instance.uniqueClients.formatted())
            }
            .font(.caption)

            syncLine
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// "Synced X ago" line using the last hourly query-log sync time (not the
    /// much-more-frequent stats poll). Falls back gracefully for servers
    /// without /api/sync/status or sites whose sync is disabled.
    @ViewBuilder
    private var syncLine: some View {
        if !instance.isActive {
            HStack(spacing: 4) {
                Image(systemName: "pause.circle").font(.caption2)
                Text("Sync disabled")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let lastSync = lastSyncAt {
            let failed = syncResult?.status == "error"
            HStack(spacing: 4) {
                Image(systemName: failed ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                    .font(.caption2)
                Text(failed ? "Sync failed" : "Synced")
                Text(lastSync, style: .relative)
                Text("ago")
            }
            .font(.caption2)
            .foregroundStyle(failed ? .red : .secondary)
        }
    }

    private var statusDot: some View {
        let color: Color = switch instance.status.lowercased() {
        case "online", "enabled", "up", "active": .green
        case "disabled", "paused": .orange
        case "offline", "error", "down": .red
        default: .gray
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
    }
}
