import SwiftUI

struct QueryLogView: View {
    @Bindable var vm: QueryLogViewModel
    @State private var showLegend = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                prompt: vm.isClientsMode ? "Search clients" : "Search domains"
            )
            .onSubmit(of: .search) {
                if !vm.isClientsMode {
                    Task { await vm.refresh() }
                }
            }
            .onChange(of: vm.searchText) { _, new in
                // Clearing the search in queries-mode should re-fetch without
                // the domain filter so the full list returns without requiring
                // a manual Submit.
                if !vm.isClientsMode, new.isEmpty {
                    Task { await vm.refresh() }
                }
            }
            .sheet(isPresented: $showLegend) {
                QueryLegendSheet()
            }
        }
        .task { await vm.loadInitial() }
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
        } else {
            List {
                ForEach(vm.queries) { query in
                    QueryRowView(query: query)
                }
                if vm.hasMore {
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
