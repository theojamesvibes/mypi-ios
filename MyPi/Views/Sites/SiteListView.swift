import SwiftUI

struct SiteListView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false

    var body: some View {
        @Bindable var state = appState
        NavigationStack {
            List {
                ForEach(Array(appState.sites.enumerated()), id: \.element.id) { idx, site in
                    NavigationLink {
                        SiteFormView(site: site)
                    } label: {
                        SiteRow(site: site, isActive: appState.activeSiteIndex == idx)
                    }
                    .onTapGesture {
                        appState.activeSiteIndex = idx
                    }
                }
                .onDelete { offsets in
                    appState.deleteSite(at: offsets)
                }
            }
            .navigationTitle("Sites")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                SetupSheet()
            }
        }
    }
}

private struct SiteRow: View {
    let site: Site
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(.headline)
                Text(site.baseURL.host() ?? site.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}
