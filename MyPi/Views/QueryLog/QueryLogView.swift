import SwiftUI

struct QueryLogView: View {
    @Bindable var vm: QueryLogViewModel
    @Environment(AppState.self) private var appState
    @State private var showLegend = false
    @State private var selectedQuery: QueryEntry?
    @State private var didApplyOpenQueryHook = false
    @State private var loadMoreSentinelVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                QueryFilterChips(vm: vm)
                resultCount
                Divider()
                listBody
            }
            .navigationTitle("Query Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLegend = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Status icon legend")
                }
                ToolbarItem(placement: .principal) {
                    SiteSwitcherMenu()
                }
            }
            .searchable(
                text: $vm.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            .sheet(isPresented: $showLegend) {
                QueryLegendSheet()
            }
            .sheet(item: $selectedQuery) { query in
                QueryDetailView(
                    query: query,
                    client: appState.client(for: vm.site),
                    range: vm.selectedRange,
                    onShowDomain: { vm.showQueries(forDomain: $0) },
                    onShowClient: { vm.showQueries(forClient: $0) }
                )
            }
        }
        .task {
            await vm.loadInitial()
            // Dev/screenshot hook: `-mypi-open-query <row>` opens the detail
            // sheet for that row once the first page is in, so automated
            // tooling can capture it headlessly. No effect without the arg.
            if let row = UserDefaults.standard.object(forKey: "mypi-open-query") as? Int ?? Int(UserDefaults.standard.string(forKey: "mypi-open-query") ?? ""),
               !didApplyOpenQueryHook, vm.queries.indices.contains(row) {
                didApplyOpenQueryHook = true
                selectedQuery = vm.queries[row]
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            if vm.site.isDemo {
                DemoModeBanner()
                    .padding(.top, 4)
            }
            LastUpdatedLabel(lastUpdated: vm.lastUpdated)
                .padding(.top, vm.site.isDemo ? 0 : 4)
            // Same confidence gate as Dashboard — only show the banner once
            // the active-site Dashboard VM has confirmed ≥ 2 consecutive
            // failures. The QueryLog VM itself doesn't poll, so we lean on
            // the Dashboard VM's failure streak as the single source of
            // truth for "is the site actually down."
            if let dashVM = appState.dashboardVM, dashVM.isSiteUnreachable {
                let state = appState.connectionStates[vm.site.id] ?? .unknown
                SiteStatusBanner(
                    siteName: vm.site.name,
                    state: state,
                    retryIntervalSeconds: dashVM.currentPollIntervalSeconds
                )
            }
        }
    }

    /// "N queries" for the current filters — the web Query Log shows the same
    /// figure above its table. While a search is active it also says how many
    /// of the *loaded* rows match, since Search doesn't reach unloaded pages.
    @ViewBuilder
    private var resultCount: some View {
        if !vm.isClientsMode, let total = vm.totalCount, !vm.queries.isEmpty {
            let searching = !vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty
            Group {
                if searching {
                    Text("\(vm.filteredQueries.count.formatted()) of \(vm.queries.count.formatted()) loaded match · \(total.formatted()) total")
                } else {
                    Text("\(total.formatted()) \(total == 1 ? "query" : "queries")")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if vm.isClientsMode {
            clientsList
        } else {
            queriesList
        }
    }

    @ViewBuilder
    private var queriesList: some View {
        if vm.queries.isEmpty && vm.isLoading {
            LoadingView()
        } else if vm.queries.isEmpty, let err = vm.errorMessage {
            ErrorView(message: err) {
                Task { await vm.refresh() }
            }
        } else if vm.queries.isEmpty {
            ContentUnavailableView {
                Label("No Queries", systemImage: "magnifyingglass")
            } description: {
                Text("No queries match the current filters.")
            } actions: {
                if vm.domainFilter != nil || vm.clientFilter != nil {
                    Button("Clear Domain & Client Filters") {
                        vm.domainFilter = nil
                        vm.clientFilter = nil
                    }
                }
            }
        } else if vm.filteredQueries.isEmpty && !vm.searchText.isEmpty {
            ContentUnavailableView.search(text: vm.searchText)
        } else {
            List {
                ForEach(vm.filteredQueries) { query in
                    Button {
                        selectedQuery = query
                    } label: {
                        QueryRowView(query: query)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows query details")
                }
                // Hide the infinite-scroll sentinel while a search is active
                // — loading more server pages won't expand what the local
                // filter matches in any useful way and it confuses the UI.
                if vm.searchText.isEmpty {
                    if let pageError = vm.pageErrorMessage {
                        VStack(spacing: 6) {
                            Text("Couldn't load more queries")
                                .font(.subheadline)
                            Text(pageError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Try Again") {
                                Task { await vm.loadNextPage() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    } else if vm.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                loadMoreSentinelVisible = true
                                Task { await vm.loadNextPage() }
                            }
                            .onDisappear { loadMoreSentinelVisible = false }
                            // `loadNextPage` is a no-op while another fetch
                            // is running, and `onAppear` won't fire again for
                            // a row that's already on screen — so re-arm
                            // when that fetch finishes, but only while the
                            // spinner really is on screen.
                            .onChange(of: vm.isLoading) { _, loading in
                                if !loading, loadMoreSentinelVisible {
                                    Task { await vm.loadNextPage() }
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await vm.refresh()
            }
        }
    }

    @ViewBuilder
    private var clientsList: some View {
        if vm.clients.isEmpty && vm.isLoading {
            LoadingView()
        } else if vm.clients.isEmpty, let err = vm.errorMessage {
            ErrorView(message: err) {
                Task { await vm.refresh() }
            }
        } else if vm.filteredClients.isEmpty && !vm.searchText.isEmpty {
            ContentUnavailableView.search(text: vm.searchText)
        } else if vm.clients.isEmpty {
            ContentUnavailableView(
                "No Clients",
                systemImage: "desktopcomputer",
                description: Text("No clients in this time range.")
            )
        } else {
            List(vm.filteredClients) { c in
                // Tapping a client drills into its queries, like following a
                // client link on the web dashboard.
                Button {
                    vm.showQueries(forClient: c.clientIp.isEmpty ? c.clientName : c.clientIp)
                } label: {
                    ClientRowView(client: c)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this client's queries")
            }
            .listStyle(.plain)
            .refreshable {
                await vm.refresh()
            }
        }
    }
}
