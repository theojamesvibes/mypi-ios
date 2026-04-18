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
                        StatCardsSection(stats: summary.totals)

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
                    TimeRangePicker(selectedHours: $vm.selectedHours)
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

private struct TimeRangePicker: View {
    @Binding var selectedHours: Int

    private let options: [(label: String, hours: Int)] = [
        ("1h", 1), ("6h", 6), ("24h", 24), ("7d", 168), ("30d", 720),
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.hours) { option in
                Button(option.label) { selectedHours = option.hours }
            }
        } label: {
            Label(labelFor(selectedHours), systemImage: "clock")
        }
    }

    private func labelFor(_ hours: Int) -> String {
        options.first(where: { $0.hours == hours })?.label ?? "\(hours)h"
    }
}

private struct StatCardsSection: View {
    let stats: SummaryStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCardView(
                title: "Total Queries",
                value: stats.dnsQueriesToday.formatted(),
                icon: "globe",
                color: .blue
            )
            StatCardView(
                title: "Blocked",
                value: "\(stats.queriesBlocked.formatted()) (\(stats.percentBlocked.formatted(.number.precision(.fractionLength(1))))%)",
                icon: "shield.fill",
                color: .red
            )
            StatCardView(
                title: "Domains on Blocklist",
                value: stats.domainsOnBlocklist.formatted(),
                icon: "list.bullet.rectangle",
                color: .orange
            )
            StatCardView(
                title: "Unique Clients",
                value: stats.uniqueClients.formatted(),
                icon: "desktopcomputer",
                color: .purple
            )
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
