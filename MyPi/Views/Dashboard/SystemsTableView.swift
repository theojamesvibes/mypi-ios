import SwiftUI

struct SystemsTableView: View {
    let instances: [InstanceSummary]

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
                        InstanceRow(instance: instance)
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
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusDot: some View {
        let color: Color = switch instance.status.lowercased() {
        case "enabled": .green
        case "disabled": .orange
        default: .red
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
