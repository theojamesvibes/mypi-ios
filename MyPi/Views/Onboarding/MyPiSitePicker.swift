import SwiftUI

/// Sheet that lets the user choose how to add a multi-site MyPi server.
/// Used by both `SetupSheet` (initial connection — shows every site) and
/// `SiteFormView` (post-setup discovery — pre-filtered to sites not yet
/// configured).
///
/// Returns one of three choices via `onChoice`:
/// - `.mainOnly`: save with `mypiSiteSlug = nil`, hitting legacy routes
///   that the server resolves to Main. Same data the user got pre-1.11.
/// - `.specific(MyPiSite)`: save one iOS Site pointing at that backend
///   site via its slug.
/// - `.all`: caller adds every offered site as a separate iOS Site,
///   activating Main and leaving the rest secondary (per the user's
///   preference set during the multi-site design discussion).
struct MyPiSitePicker: View {
    let serverName: String
    let sites: [MyPiSite]
    /// When true, hides the "Use Main only" option — used by the
    /// post-setup discovery path where the user already has an entry
    /// covering Main and is just looking to add siblings.
    var hidesMainOnlyOption: Bool = false
    let onChoice: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Choice {
        case mainOnly
        case specific(MyPiSite)
        case all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(serverName) hosts \(sites.count) sites. Choose how to add it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !hidesMainOnlyOption {
                    Section {
                        choiceButton(
                            title: "Use Main site only",
                            subtitle: "Recommended. Uses the server's default site via legacy routes.",
                            systemImage: "star.fill"
                        ) {
                            onChoice(.mainOnly)
                            dismiss()
                        }
                    } header: {
                        Text("Default")
                    }
                }

                Section {
                    ForEach(sites) { mypiSite in
                        Button {
                            onChoice(.specific(mypiSite))
                            dismiss()
                        } label: {
                            siteRow(mypiSite)
                        }
                    }
                } header: {
                    Text(hidesMainOnlyOption ? "Available sites" : "Pick one site")
                }

                if sites.count > 1 {
                    Section {
                        choiceButton(
                            title: "Add all \(sites.count) sites",
                            subtitle: "Creates one entry per site. \(mainName ?? "Main") becomes active.",
                            systemImage: "rectangle.stack.fill.badge.plus"
                        ) {
                            onChoice(.all)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Choose Sites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var mainName: String? {
        sites.first(where: { $0.isMain })?.name
    }

    @ViewBuilder
    private func choiceButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func siteRow(_ mypiSite: MyPiSite) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mypiSite.name)
                        .foregroundStyle(.primary)
                    if mypiSite.isMain {
                        mainBadge
                    }
                }
                Text(metadata(for: mypiSite))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var mainBadge: some View {
        Text("Main")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private func metadata(for mypiSite: MyPiSite) -> String {
        let count = mypiSite.activeInstanceCount
        let unit = count == 1 ? "instance" : "instances"
        return "/\(mypiSite.slug) · \(count) \(unit)"
    }
}
