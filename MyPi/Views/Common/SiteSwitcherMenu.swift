import SwiftUI

/// Menu used in the toolbar of Dashboard, Query Log, and Settings to switch
/// between configured sites. Renders only when more than one site is
/// configured — otherwise there's nothing to pick from.
struct SiteSwitcherMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.sites.count > 1, let active = appState.activeSite {
            Menu {
                ForEach(Array(appState.sites.enumerated()), id: \.element.id) { idx, site in
                    Button {
                        appState.activeSiteIndex = idx
                    } label: {
                        HStack {
                            Text(site.name)
                            if site.id == active.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(active.name).bold()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.primary)
            }
        } else if let active = appState.activeSite {
            Text(active.name).bold()
        }
    }
}
