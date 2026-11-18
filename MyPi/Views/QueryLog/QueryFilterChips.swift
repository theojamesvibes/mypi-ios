import SwiftUI

/// Row of tappable pill chips shown above the Query Log list.
/// Each chip shows its current selection and opens a Menu on tap,
/// which is clearer than hiding filters behind a single toolbar icon.
struct QueryFilterChips: View {
    @Bindable var vm: QueryLogViewModel

    var body: some View {
        // Horizontal scroll keeps three chips usable on narrow iPhones
        // (a long Pi-hole device name can't squeeze the other chips).
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(QueryFilter.allCases) { filter in
                        Button {
                            vm.filter = filter
                        } label: {
                            if vm.filter == filter {
                                Label(filter.label, systemImage: "checkmark")
                            } else {
                                Text(filter.label)
                            }
                        }
                    }
                } label: {
                    ChipLabel(
                        title: "Filter",
                        value: vm.filter.label,
                        tint: vm.filter == .all ? .secondary : .accentColor
                    )
                }

                Menu {
                    ForEach(TimeRange.allCases) { range in
                        Button {
                            vm.selectedRange = range
                        } label: {
                            if vm.selectedRange == range {
                                Label(range.longLabel, systemImage: "checkmark")
                            } else {
                                Text(range.longLabel)
                            }
                        }
                    }
                } label: {
                    ChipLabel(
                        title: "When",
                        value: vm.selectedRange.label,
                        tint: .accentColor
                    )
                }

                // Device chip mirrors the web Query Log's instance dropdown.
                // Hidden with fewer than two devices — nothing to choose.
                if vm.instances.count > 1 {
                    Menu {
                        Button {
                            vm.selectedInstanceId = nil
                        } label: {
                            if vm.selectedInstanceId == nil {
                                Label("All Devices", systemImage: "checkmark")
                            } else {
                                Text("All Devices")
                            }
                        }
                        Divider()
                        ForEach(vm.instances) { instance in
                            Button {
                                vm.selectedInstanceId = instance.id
                            } label: {
                                if vm.selectedInstanceId == instance.id {
                                    Label(instance.name, systemImage: "checkmark")
                                } else {
                                    Text(instance.name)
                                }
                            }
                        }
                    } label: {
                        ChipLabel(
                            title: "Device",
                            value: vm.selectedInstanceName ?? "All",
                            tint: vm.selectedInstanceId == nil ? .secondary : .accentColor
                        )
                    }
                }

                // Drill-down filters set from the query detail screen (the
                // web Query Log's Domain / Client boxes). Tap to clear.
                if let domain = vm.domainFilter {
                    RemovableChip(title: "Domain", value: domain) {
                        vm.domainFilter = nil
                    }
                }
                if let client = vm.clientFilter {
                    RemovableChip(title: "Client", value: client) {
                        vm.clientFilter = nil
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.background)
    }
}

private struct ChipLabel: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline).bold()
                .foregroundStyle(tint)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
    }
}

/// A chip for a filter that has no menu of choices — it's either applied or
/// not, so the whole chip is a "remove" button.
private struct RemovableChip: View {
    let title: String
    let value: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline).bold()
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) filter: \(value)")
        .accessibilityHint("Removes this filter")
    }
}
