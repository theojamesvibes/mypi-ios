import SwiftUI

/// Multi-select picklist shown when a multi-site MyPi server (1.11+) is
/// detected. Used by both `SetupSheet` (initial connection — lists every
/// site, with Main pre-selected) and `SiteFormView` (post-setup discovery
/// — pre-filtered to sites not yet configured).
///
/// The user ticks whichever sites they want and taps **Add**; the selected
/// `[MyPiSite]` set is handed back via `onAdd`. The caller decides how to
/// commit them (name suffixes, which becomes active, Keychain writes).
/// Returning the raw selection keeps this view free of any Site/Keychain
/// knowledge — it's purely a checklist.
struct MyPiSitePicker: View {
    let serverName: String
    let sites: [MyPiSite]
    /// Site IDs ticked when the sheet first appears. `SetupSheet` passes
    /// Main here so the common "just add this server" case is one tap;
    /// the discovery flow passes nothing, leaving the user to choose.
    var preselected: Set<MyPiSite.ID> = []
    /// Called with the chosen sites (always non-empty — the Add button is
    /// disabled when the selection is empty).
    let onAdd: ([MyPiSite]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<MyPiSite.ID> = []

    private var orderedSites: [MyPiSite] {
        sites.sorted { lhs, rhs in
            // Main first, then sortOrder, then name (stable fallback) — same
            // ordering the commit path uses, so the list reads top-to-bottom
            // in the order entries get created.
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedCount: Int { selected.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(serverName) hosts \(sites.count) sites. Select the ones you want to add — each becomes its own entry you can switch between.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(orderedSites) { mypiSite in
                        Button {
                            toggle(mypiSite.id)
                        } label: {
                            siteRow(mypiSite, isOn: selected.contains(mypiSite.id))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Sites")
                }
            }
            .navigationTitle("Add Sites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) {
                        let chosen = orderedSites.filter { selected.contains($0.id) }
                        onAdd(chosen)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear {
                // Seed once. Guard against re-seeding on a re-render so a
                // user who deliberately unticked Main doesn't get it back.
                if selected.isEmpty { selected = preselected }
            }
        }
    }

    private var addButtonTitle: String {
        selectedCount > 1 ? "Add \(selectedCount)" : "Add"
    }

    private func toggle(_ id: MyPiSite.ID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    @ViewBuilder
    private func siteRow(_ mypiSite: MyPiSite, isOn: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mypiSite.name)
                        .foregroundStyle(.primary)
                    if mypiSite.isMain {
                        mainBadge
                    }
                }
                Text(metadata(for: mypiSite))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var mainBadge: some View {
        Text("Main")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private func metadata(for mypiSite: MyPiSite) -> String {
        let count = mypiSite.activeInstanceCount
        let unit = count == 1 ? "instance" : "instances"
        return "/\(mypiSite.slug) · \(count) \(unit)"
    }
}
