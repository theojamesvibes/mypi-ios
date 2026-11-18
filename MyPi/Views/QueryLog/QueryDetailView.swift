import SwiftUI
import UIKit

/// Everything the server knows about one logged DNS query, opened by tapping
/// a row in the Query Log. Mirrors the columns of the MyPi web Query Log
/// (time, instance, domain, type, client, status, reply time) plus the
/// read-only half of its "Manage domain" dialog: allow/deny-list membership
/// and, for blocked queries, which list did the blocking.
struct QueryDetailView: View {
    let query: QueryEntry
    let client: APIClient
    /// Window used for the "blocked N times" context figure — the range the
    /// Query Log is currently showing.
    let range: TimeRange
    /// Narrow the Query Log to this query's domain / client. The sheet
    /// dismisses itself first.
    let onShowDomain: (String) -> Void
    let onShowClient: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lists: DomainListsState = .loading
    @State private var copied: String?

    private enum DomainListsState {
        case loading
        /// The domain can't be looked up (empty, or not a plain hostname).
        case unavailable
        case loaded(status: DomainListStatus, blocklists: DomainBlocklists?)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                querySection
                clientSection
                listsSection
                actionsSection
            }
            .navigationTitle("Query")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task(id: query.id) { await loadLists() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(query.domain.isEmpty ? "(no domain)" : query.domain)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: query.statusKind.systemImage)
                    Text(query.statusKind.title)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(query.statusKind.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(query.statusKind.tint.opacity(0.14)))
                .accessibilityElement(children: .combine)
                if let explanation = QueryGlossary.statusExplanation(query.status) {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var querySection: some View {
        Section("Query") {
            DetailRow(label: "Time") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(query.date.formatted(date: .abbreviated, time: .standard))
                    Text(query.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    + Text(" ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            DetailRow(
                label: "Type",
                value: query.queryType,
                note: query.queryType.flatMap(QueryGlossary.queryTypeExplanation)
            )
            DetailRow(label: "Status", value: query.status.isEmpty ? nil : query.status)
            DetailRow(
                label: "Reply",
                value: query.replyType,
                note: query.replyType.flatMap(QueryGlossary.replyTypeExplanation)
            )
            DetailRow(label: "Reply time", value: Self.replyTimeText(query.replyTimeMs))
            if let instance = query.instanceName, !instance.isEmpty {
                DetailRow(label: "Answered by", value: instance)
            }
        }
    }

    private var clientSection: some View {
        Section("Client") {
            DetailRow(label: "Name", value: query.clientName)
            DetailRow(label: "IP address", value: query.clientIp.isEmpty ? nil : query.clientIp)
        }
    }

    @ViewBuilder
    private var listsSection: some View {
        switch lists {
        case .unavailable:
            EmptyView()
        case .loading:
            Section("Domain lists") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking your Pi-hole…")
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't check list status")
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Try Again") {
                    Task { await loadLists() }
                }
            } header: {
                Text("Domain lists")
            }
        case .loaded(let status, let blocklists):
            Section {
                DetailRow(label: "Allow list", value: status.inAllow ? "Listed" : "Not listed")
                DetailRow(label: "Deny list", value: status.inDeny ? "Listed" : "Not listed")
            } header: {
                Text("Domain lists")
            } footer: {
                Text(Self.listSummary(status: status, queryBlocked: query.isBlocked))
            }
            if let blocklists, !blocklists.lists.isEmpty {
                Section {
                    ForEach(blocklists.lists) { entry in
                        BlocklistRow(entry: entry)
                    }
                } header: {
                    Text("Blocked by")
                } footer: {
                    if blocklists.blockCount > 0 {
                        Text("Blocked by an adlist \(blocklists.blockCount.formatted()) time\(blocklists.blockCount == 1 ? "" : "s") in this time range (\(range.longLabel.lowercased())).")
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if !query.domain.isEmpty {
                Button {
                    dismiss()
                    onShowDomain(query.domain)
                } label: {
                    Label("Show Queries for This Domain", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            if let clientKey = clientFilterValue {
                Button {
                    dismiss()
                    onShowClient(clientKey)
                } label: {
                    Label("Show Queries from This Client", systemImage: "desktopcomputer")
                }
            }
            if !query.domain.isEmpty {
                Button {
                    UIPasteboard.general.string = query.domain
                    copied = query.domain
                } label: {
                    Label(copied == query.domain ? "Copied" : "Copy Domain",
                          systemImage: copied == query.domain ? "checkmark" : "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Helpers

    /// The IP identifies a client exactly; fall back to the name only when
    /// the row has no IP.
    private var clientFilterValue: String? {
        if !query.clientIp.isEmpty { return query.clientIp }
        if let name = query.clientName, !name.isEmpty { return name }
        return nil
    }

    private func loadLists() async {
        guard APIClient.domainPathSegment(query.domain) != nil else {
            lists = .unavailable
            return
        }
        lists = .loading
        do {
            let status = try await client.domainStatus(query.domain)
            // "Which list blocked this?" only applies to blocked queries, and
            // it costs the server a live search on the master Pi-hole (a
            // rate-limited endpoint), so it's skipped for permitted ones.
            // Servers before 2.6.0 don't have it — that's not an error here.
            var blocklists: DomainBlocklists?
            if query.isBlocked {
                blocklists = try? await client.domainBlocklists(query.domain, range: range)
            }
            guard !Task.isCancelled else { return }
            lists = .loaded(status: status, blocklists: blocklists)
        } catch {
            guard !Task.isCancelled else { return }
            lists = .failed(ErrorMessage.userFacing(error))
        }
    }

    static func replyTimeText(_ ms: Double?) -> String? {
        guard let ms, ms >= 0, ms.isFinite else { return nil }
        if ms >= 1000 {
            return (ms / 1000).formatted(.number.precision(.fractionLength(2))) + " s"
        }
        return ms.formatted(.number.precision(.fractionLength(1))) + " ms"
    }

    /// Same wording rules as the web "Manage domain" dialog.
    static func listSummary(status: DomainListStatus, queryBlocked: Bool) -> String {
        if status.inDeny && status.inAllow {
            return "This domain is on both lists. The allow list takes priority."
        }
        switch status.effective {
        case "denied":
            return "Blocked — this domain is on the deny list."
        case "allowed":
            return "Allowed — this domain has an allow-list override."
        default:
            return queryBlocked
                ? "Not on your allow or deny list — this query was blocked by an adlist or rule."
                : "Not on your allow or deny list."
        }
    }
}

// MARK: - Rows

/// Label on the left, value (and an optional plain-English note) on the
/// right. A nil or empty value renders as an em dash so the layout is the
/// same for every query. Long-press copies the value.
private struct DetailRow<Trailing: View>: View {
    let label: String
    let copyValue: String?
    @ViewBuilder let trailing: () -> Trailing

    init(label: String, copyValue: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.copyValue = copyValue
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
                .multilineTextAlignment(.trailing)
        }
        .contextMenu {
            if let copyValue {
                Button {
                    UIPasteboard.general.string = copyValue
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DetailValue: View {
    let value: String?
    let note: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let value, !value.isEmpty {
                Text(value)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Not available")
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension DetailRow where Trailing == DetailValue {
    init(label: String, value: String?, note: String? = nil) {
        let present = (value?.isEmpty == false) ? value : nil
        self.init(label: label, copyValue: present) {
            DetailValue(value: present, note: present == nil ? nil : note)
        }
    }
}

private struct BlocklistRow: View {
    let entry: DomainBlocklists.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.name)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.isSecurity {
                    Label("Security", systemImage: "exclamationmark.shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
            }
            Text(entry.enabled ? entry.kindLabel : "\(entry.kindLabel) · disabled")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let address = entry.address, !address.isEmpty {
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}

extension QueryStatusKind {
    var tint: Color {
        switch self {
        case .blocked: return .red
        case .cached: return .blue
        case .permitted: return .green
        case .other: return .secondary
        }
    }
}
