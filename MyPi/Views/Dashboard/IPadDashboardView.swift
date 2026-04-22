import SwiftUI

/// iPad-native Dashboard layout modelled on the MyPi web dashboard:
/// 4-wide stat row, time-series chart + Query Types donut side-by-side,
/// Pi-hole systems table, and 3-column top-lists.
struct IPadDashboardView: View {
    @Bindable var vm: DashboardViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LastUpdatedLabel(lastUpdated: vm.lastUpdated)
                    .padding(.top, 4)

                if vm.isSiteUnreachable {
                    let state = appState.connectionStates[vm.site.id] ?? .unknown
                    SiteStatusBanner(
                        siteName: vm.site.name,
                        state: state,
                        retryIntervalSeconds: vm.currentPollIntervalSeconds
                    )
                }

                if let lastUpdated = vm.lastUpdated, vm.isStale {
                    StaleDataBanner(lastUpdated: lastUpdated)
                }

                if let summary = vm.summary {
                    StatRow(stats: summary.totals)
                        .padding(.horizontal)

                    HStack(alignment: .top, spacing: 16) {
                        if let history = vm.history, !history.buckets.isEmpty {
                            QueryActivityChart(
                                history: history,
                                range: vm.selectedRange,
                                height: 180,
                                cardHeight: 280
                            )
                            .frame(maxWidth: .infinity)
                        }
                        QueryTypesDonut(stats: summary.totals, cardHeight: 280)
                            .frame(width: 320)
                    }
                    .padding(.horizontal)

                    if let top = vm.top {
                        TopListsRow(top: top)
                            .padding(.horizontal)
                    }

                    SystemsTableView(
                        instances: summary.instances,
                        syncStatus: vm.syncStatus
                    )
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
            .padding(.vertical, 12)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SiteSwitcherMenu()
            }
            ToolbarItem(placement: .topBarTrailing) {
                TimeRangeMenuPicker(selection: $vm.selectedRange)
            }
        }
        .refreshable {
            await vm.refresh()
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

private struct StatRow: View {
    let stats: SummaryStats

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            StatCardView(
                title: "Total Queries",
                value: stats.dnsQueriesToday.formatted(),
                icon: "globe",
                color: .blue
            )
            StatCardView(
                title: "Queries Blocked",
                value: stats.queriesBlocked.formatted(),
                icon: "shield.fill",
                color: .red
            )
            StatCardView(
                title: "Percent Blocked",
                value: "\(stats.percentBlocked.formatted(.number.precision(.fractionLength(1))))%",
                icon: "percent",
                color: .orange
            )
            StatCardView(
                title: "Domains on Blocklist",
                value: stats.domainsOnBlocklist.formatted(),
                icon: "list.bullet.rectangle",
                color: .green
            )
        }
    }
}

/// 3-column arrangement of the top tables — matches the mypi web layout.
private struct TopListsRow: View {
    let top: TopStatsResponse

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), alignment: .leading, spacing: 16) {
            TopColumn(
                title: "Top Permitted Domains",
                icon: "checkmark.circle",
                color: .green,
                items: top.topPermitted.map { ($0.domain, $0.count) }
            )
            TopColumn(
                title: "Top Blocked Domains",
                icon: "shield.slash",
                color: .red,
                items: top.topBlocked.map { ($0.domain, $0.count) }
            )
            TopColumn(
                title: "Top Clients",
                icon: "desktopcomputer",
                color: .purple,
                items: top.topClients.map { ($0.client, $0.count) }
            )
        }
    }
}

private struct TopColumn: View {
    let title: String
    let icon: String
    let color: Color
    let items: [(String, Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
                .padding()
            Divider()
            ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { idx, item in
                HStack {
                    Text(item.0)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(item.1.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                if idx < min(items.count, 10) - 1 {
                    Divider().padding(.leading)
                }
            }
            if items.isEmpty {
                Text("No data").font(.footnote).foregroundStyle(.secondary).padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
