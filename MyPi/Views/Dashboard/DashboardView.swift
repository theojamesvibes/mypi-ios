import SwiftUI

struct DashboardView: View {
    @Bindable var vm: DashboardViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let lastUpdated = vm.lastUpdated, vm.isStale {
                        StaleDataBanner(lastUpdated: lastUpdated)
                    }

                    if let summary = vm.summary {
                        StatCardsSection(stats: summary.totals, vm: vm, appState: appState)

                        if let history = vm.history, !history.buckets.isEmpty {
                            QueryHistoryChart(history: history)
                                .padding(.horizontal)
                        }

                        if let top = vm.top {
                            TopListsView(top: top)
                        }

                        SystemsTableView(instances: summary.instances)
                    } else {
                        switch vm.loadState {
                        case .loading, .idle:
                            LoadingView()
                        case .failed(let msg):
                            ErrorView(message: msg) {
                                Task { await vm.refresh() }
                            }
                        case .loaded:
                            EmptyView()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle(appState.activeSite?.name ?? "Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TimeRangeMenuPicker(selection: $vm.selectedRange)
                }
            }
            .refreshable {
                await vm.refresh()
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

private struct StatCardsSection: View {
    let stats: SummaryStats
    let vm: DashboardViewModel
    let appState: AppState

    private var client: APIClient? {
        appState.activeSite.map { appState.client(for: $0) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCardView(
                title: "Total Queries",
                value: stats.dnsQueriesToday.formatted(),
                icon: "globe",
                color: .blue
            )
            if let client {
                NavigationLink {
                    BlockedDrilldownView(client: client, range: vm.selectedRange)
                } label: {
                    StatCardView(
                        title: "Blocked",
                        value: "\(stats.queriesBlocked.formatted()) (\(stats.percentBlocked.formatted(.number.precision(.fractionLength(1))))%)",
                        icon: "shield.fill",
                        color: .red,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                StatCardView(
                    title: "Blocked",
                    value: "\(stats.queriesBlocked.formatted()) (\(stats.percentBlocked.formatted(.number.precision(.fractionLength(1))))%)",
                    icon: "shield.fill",
                    color: .red
                )
            }
            StatCardView(
                title: "Domains on Blocklist",
                value: stats.domainsOnBlocklist.formatted(),
                icon: "list.bullet.rectangle",
                color: .orange
            )
            if let client {
                NavigationLink {
                    ClientsDrilldownView(client: client, range: vm.selectedRange)
                } label: {
                    StatCardView(
                        title: "Unique Clients",
                        value: stats.uniqueClients.formatted(),
                        icon: "desktopcomputer",
                        color: .purple,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                StatCardView(
                    title: "Unique Clients",
                    value: stats.uniqueClients.formatted(),
                    icon: "desktopcomputer",
                    color: .purple
                )
            }
            StatCardView(
                title: "Cached",
                value: stats.queriesCached.formatted(),
                icon: "memorychip",
                color: .teal
            )
            StatCardView(
                title: "Forwarded",
                value: stats.queriesForwarded.formatted(),
                icon: "arrow.up.forward",
                color: .green
            )
        }
        .padding(.horizontal)
    }
}
