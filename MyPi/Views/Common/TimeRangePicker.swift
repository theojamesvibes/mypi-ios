import SwiftUI

/// Menu-style time range picker, shared by Dashboard and Query Log toolbars.
struct TimeRangeMenuPicker: View {
    @Binding var selection: TimeRange

    var body: some View {
        Menu {
            ForEach(TimeRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    if selection == range {
                        Label(range.longLabel, systemImage: "checkmark")
                    } else {
                        Text(range.longLabel)
                    }
                }
            }
        } label: {
            Label(selection.label, systemImage: "clock")
        }
    }
}
