import SwiftUI

struct QueryLogView: View {
    @Bindable var vm: QueryLogViewModel
    @Environment(AppState.self) private var appState
    @State private var showLegend = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                QueryFilterChips(vm: vm)
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
        }
        .task { await vm.loadInitial() }
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
            ContentUnavailableView(
                "No Queries",
                systemImage: "magnifyingglass",
                description: Text("No queries match the current filter.")
            )
        } else if vm.filteredQueries.isEmpty && !vm.searchText.isEmpty {
            ContentUnavailableView.search(text: vm.searchText)
        } else {
            List {
                ForEach(vm.filteredQueries) { query in
                    QueryRowView(query: query)
                }
                // Hide the infinite-scroll sentinel while a search is active
                // — loading more server pages won't expand what the local
                // filter matches in any useful way and it confuses the UI.
                if vm.hasMore, vm.searchText.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            Task { await vm.loadNextPage() }
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
                ClientRowView(client: c)
            }
            .listStyle(.plain)
            .refreshable {
                await vm.refresh()
            }
        }
    }
}
