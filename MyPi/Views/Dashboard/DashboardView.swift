import SwiftUI

struct DashboardView: View {
    @Bindable var vm: DashboardViewModel
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        NavigationStack {
            if hSize == .regular {
                IPadDashboardView(vm: vm)
            } else {
                phoneBody
            }
        }
    }

    @ViewBuilder
    private var phoneBody: some View {
        ScrollViewReader { proxy in
            phoneScroll
                .task {
                    // Dev/screenshot hook: `-mypi-scroll-to chart|donut|toplists`
                    // scrolls the anchor to the top after the demo data has
                    // rendered, so tooling can capture below-the-fold cards
                    // headlessly (the simulator can't be scrolled via CLI).
                    guard let anchor = UserDefaults.standard.string(forKey: "mypi-scroll-to") else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                }
        }
    }

    @ViewBuilder
    private var phoneScroll: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if vm.site.isDemo {
                    DemoModeBanner()
                        .padding(.top, 4)
                }

                LastUpdatedLabel(lastUpdated: vm.lastUpdated)
                    .padding(.top, vm.site.isDemo ? 0 : 4)

                // Gate on vm.isSiteUnreachable so the banner only appears
                // once the VM has confirmed ≥ 2 consecutive fetch failures.
                // A one-off transient error leaves state-based .error behind
                // but we don't trust it until the VM agrees.
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
                    StatCardsSection(stats: summary.totals)

                    if let history = vm.history, !history.buckets.isEmpty {
                        QueryActivityChart(vm: vm, history: history, range: vm.selectedRange, height: 160)
                            .padding(.horizontal)
                            .id("chart")
                    }

                    QueryTypesDonut(stats: summary.totals)
                        .padding(.horizontal)
                        .id("donut")

                    if let top = vm.top {
                        TopListsView(top: top)
                            .id("toplists")
                    }

                    SystemsTableView(instances: summary.instances, syncStatus: vm.syncStatus)
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
