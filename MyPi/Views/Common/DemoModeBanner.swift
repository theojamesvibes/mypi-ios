import SwiftUI

/// Persistent indicator shown above every tab's content whenever the active
/// site is a demo site. Two jobs:
///
/// 1. Tell the user the data they're looking at is synthetic (and therefore
///    not the real state of their Pi-hole setup — matters for anyone who's
///    both demoing and has a real server).
/// 2. Document the exit path. Demo sites auto-clear on cold launch
///    (`AppState.init` removes them), so the only way out is to close the
///    app from the app switcher. That's non-obvious without a hint.
struct DemoModeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(Color.accentColor)
                .font(.subheadline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo Mode")
                    .font(.footnote).bold()
                Text("Showing sample data · Close the app to exit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.accentColor.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo Mode. Showing sample data. Close the app to exit demo mode.")
    }
}
