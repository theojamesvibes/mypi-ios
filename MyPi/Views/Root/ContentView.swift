import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var state = appState
        Group {
            if appState.sites.isEmpty {
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

private struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selectedTab: TabID = .dashboard

    private enum TabID: Int, Hashable, CaseIterable {
        case dashboard, queryLog, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.fill", value: TabID.dashboard) {
                if let vm = appState.dashboardVM {
                    // .id(site) forces SwiftUI to rebuild the view when the
                    // active site changes, firing the old vm's .onDisappear
                    // (stopping its poll) and the new vm's .onAppear so the
                    // two site states don't interleave.
                    DashboardView(vm: vm)
                        .id(vm.site.id)
                }
            }
            Tab("Query Log", systemImage: "list.bullet", value: TabID.queryLog) {
                if let vm = appState.queryLogVM {
                    QueryLogView(vm: vm)
                        .id(vm.site.id)
                }
            }
            Tab("Settings", systemImage: "gear", value: TabID.settings) {
                AppSettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Horizontal swipe switches tabs. Skipped on iPad where the
        // sidebar owns horizontal drags and mis-fires would be disruptive.
        // simultaneousGesture so List/ScrollView verticals still work; the
        // |dx| > |dy| check filters vertical scrolls out.
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard hSize == .compact else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5 else { return }
                    let all = TabID.allCases
                    guard let idx = all.firstIndex(of: selectedTab) else { return }
                    if dx < 0, idx < all.count - 1 {
                        selectedTab = all[idx + 1]
                    } else if dx > 0, idx > 0 {
                        selectedTab = all[idx - 1]
                    }
                }
        )
    }
}
