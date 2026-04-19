import SwiftUI

/// Row of tappable pill chips shown above the Query Log list.
/// Each chip shows its current selection and opens a Menu on tap,
/// which is clearer than hiding filters behind a single toolbar icon.
struct QueryFilterChips: View {
    @Bindable var vm: QueryLogViewModel

    var body: some View {
        HStack(spacing: 8) {
            Menu {
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
            } label: {
                ChipLabel(
                    title: "Filter",
                    value: vm.filter.label,
                    tint: vm.filter == .all ? .secondary : .accentColor
                )
            }

            Menu {
                ForEach(TimeRange.allCases) { range in
                    Button {
                        vm.selectedRange = range
                    } label: {
                        if vm.selectedRange == range {
                            Label(range.longLabel, systemImage: "checkmark")
                        } else {
                            Text(range.longLabel)
                        }
                    }
                }
            } label: {
                ChipLabel(
                    title: "When",
                    value: vm.selectedRange.label,
                    tint: .accentColor
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background)
    }
}

private struct ChipLabel: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline).bold()
                .foregroundStyle(tint)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
    }
}
