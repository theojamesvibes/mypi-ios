import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

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

    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.fill") {
                if let vm = appState.dashboardVM {
                    DashboardView(vm: vm)
                }
            }
            Tab("Query Log", systemImage: "list.bullet") {
                if let vm = appState.queryLogVM {
                    QueryLogView(vm: vm)
                }
            }
            Tab("Sites", systemImage: "server.rack") {
                SiteListView()
            }
            Tab("Settings", systemImage: "gear") {
                AppSettingsView()
            }
        }
    }
}
