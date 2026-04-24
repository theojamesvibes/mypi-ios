import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var state = appState
        Group {
            if let err = appState.loadError {
                SitesLoadErrorView(message: err)
            } else if appState.sites.isEmpty {
                EmptyStateView()
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: $state.showSetupSheet) {
            SetupSheet()
        }
        .onChange(of: scenePhase) { _, phase in
            // Refresh whenever the app comes back to the foreground. Replaces
            // the old BGAppRefreshTask plumbing — cheaper, more predictable,
            // and the data is fresh exactly when the user can see it.
            if phase == .active {
                Task {
                    await appState.dashboardVM?.refresh()
                    await appState.queryLogVM?.refresh()
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 24) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Sites Configured")
                .font(.title2).bold()
            Text("Add your first MyPi server to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Site") {
                state.showSetupSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// Shown when `SiteStore.load()` threw on launch — `sites.json` is on disk
/// but can't be decoded. Intentionally doesn't offer a "reset" button:
/// if the user could one-tap nuke the file, a momentary decode glitch
/// would destroy recoverable data. Recovery path is to reinstall (or
/// delete the file via the Files app if they know what they're doing).
private struct SitesLoadErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't load your sites")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Delete and reinstall the app to start over. Note: this will remove all site configurations and cached data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

private enum MainTab: Int, Hashable, CaseIterable {
    case dashboard, queryLog, settings

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .queryLog:  return "Query Log"
        case .settings:  return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .queryLog:  return "list.bullet"
        case .settings:  return "gearshape.fill"
        }
    }
}

/// Paging + custom bottom bar. `TabView` with `.page` style is backed by
/// `UIPageViewController`, so horizontal swipes produce a real interactive
/// slide (half-swipe peek, spring snap) instead of the instant cross-fade
/// the stock `.automatic` style emits when `selection` changes. The custom
/// bar replaces the chrome that `.page` style strips.
///
/// Works identically on iPhone and iPad — previously iPad used
/// `.sidebarAdaptable` and swipes were gated out because the sidebar owned
/// horizontal drags; switching to `.page` gives iPad the same swipe behavior
/// without that conflict.
private struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selected: MainTab = .dashboard

    var body: some View {
        TabView(selection: $selected) {
            dashboard
                .tag(MainTab.dashboard)
            queryLog
                .tag(MainTab.queryLog)
            AppSettingsView()
                .tag(MainTab.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomTabBar(selected: $selected)
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        if let vm = appState.dashboardVM {
            // .id(site) forces SwiftUI to rebuild the view when the active
            // site changes, firing the old vm's .onDisappear (stopping its
            // poll) and the new vm's .onAppear so the two site states don't
            // interleave.
            DashboardView(vm: vm).id(vm.site.id)
        }
    }

    @ViewBuilder
    private var queryLog: some View {
        if let vm = appState.queryLogVM {
            QueryLogView(vm: vm).id(vm.site.id)
        }
    }
}

private struct BottomTabBar: View {
    @Binding var selected: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    // No explicit `withAnimation` here — `TabView(.page)`
                    // has its own spring that drives both the interactive
                    // swipe and programmatic selection changes. Wrapping
                    // the mutation in an `easeInOut` curve earlier forced
                    // SwiftUI to cross-fade the Form-backed Settings tab
                    // instead of sliding it, which felt like an abrupt
                    // flash compared to the ScrollView-backed Dashboard /
                    // Query Log slides.
                    selected = tab
                } label: {
                    tabLabel(for: tab)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == tab ? .isSelected : [])
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabLabel(for tab: MainTab) -> some View {
        let active = selected == tab
        return VStack(spacing: 2) {
            Image(systemName: tab.icon)
                .font(.system(size: 22, weight: active ? .semibold : .regular))
            Text(tab.label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .contentShape(Rectangle())
    }
}
