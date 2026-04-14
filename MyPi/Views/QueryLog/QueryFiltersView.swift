import SwiftUI

struct QueryFiltersView: View {
    @Bindable var vm: QueryLogViewModel

    private let hourOptions: [(String, Int)] = [
        ("1h", 1), ("6h", 6), ("24h", 24), ("7d", 168), ("30d", 720),
    ]

    var body: some View {
        Menu {
            Section("Type") {
                ForEach(QueryFilter.allCases) { filter in
                    Button {
                        vm.filter = filter
                    } label: {
                        if vm.filter == filter {
                            Label(filter.label, systemImage: "checkmark")
                        } else {
                            Text(filter.label)
                        }
                    }
                }
            }
            Section("Time Range") {
                ForEach(hourOptions, id: \.1) { label, hours in
                    Button {
                        vm.selectedHours = hours
                    } label: {
                        if vm.selectedHours == hours {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}
