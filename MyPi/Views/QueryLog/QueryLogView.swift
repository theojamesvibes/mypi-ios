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
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLegend = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Status icon legend")
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
}
