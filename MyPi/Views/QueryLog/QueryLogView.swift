import SwiftUI

struct QueryLogView: View {
    @Bindable var vm: QueryLogViewModel

    var body: some View {
        NavigationStack {
            Group {
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
                }
            }
            .navigationTitle("Query Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    QueryFiltersView(vm: vm)
                }
            }
            .refreshable {
                await vm.refresh()
            }
        }
        .task { await vm.loadInitial() }
    }
}
