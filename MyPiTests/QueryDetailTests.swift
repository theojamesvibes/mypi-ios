import Foundation
import Testing
@testable import MyPi

// MARK: - Query detail decoding

struct QueryDetailDecodingTests {
    private func decode(_ json: String) throws -> QueryEntry {
        try makeAPIDecoder().decode(QueryEntry.self, from: Data(json.utf8))
    }

    @Test func decodesDetailFields() throws {
        let q = try decode("""
        {"id":"1","timestamp":"2026-05-25T12:30:45","domain":"example.com",
         "client_ip":"192.168.1.5","client_name":"laptop","status":"FORWARDED",
         "instance_id":"pi1","instance_name":"Pi One",
         "query_type":"AAAA","reply_type":"IP","reply_time_ms":12.5}
        """)
        #expect(q.queryType == "AAAA")
        #expect(q.replyType == "IP")
        #expect(q.replyTimeMs == 12.5)
    }

    /// The server schema marks these nullable. One such row used to fail the
    /// decode of the entire page, leaving the Query Log empty.
    @Test func nullTextFieldsDecodeInsteadOfFailingThePage() throws {
        let json = """
        {"items":[
          {"id":"1","timestamp":"2026-05-25T12:30:45","domain":null,
           "client_ip":null,"client_name":null,"status":null,
           "instance_id":"pi1","instance_name":"Pi One",
           "query_type":null,"reply_type":null,"reply_time_ms":null},
          {"id":"2","timestamp":"2026-05-25T12:30:46","domain":"ok.example.com",
           "client_ip":"10.0.0.2","status":"CACHE"}
        ],"total":2,"page":1,"page_size":50}
        """
        let page = try makeAPIDecoder().decode(QueryPage.self, from: Data(json.utf8))
        #expect(page.items.count == 2)
        let empty = page.items[0]
        #expect(empty.domain == "")
        #expect(empty.clientIp == "")
        #expect(empty.status == "")
        #expect(empty.queryType == nil)
        #expect(empty.replyTimeMs == nil)
        #expect(empty.statusKind == .other)
        #expect(empty.clientDisplayName == "Unknown client")
    }

    /// Pages cached to disk by 0.4.0 don't have the detail keys.
    @Test func roundTripsThroughTheDiskCacheEncoding() throws {
        let original = try decode("""
        {"id":"1","timestamp":"2026-05-25T12:30:45Z","domain":"example.com",
         "client_ip":"192.168.1.5","status":"GRAVITY","query_type":"A"}
        """)
        let data = try JSONEncoder().encode([original])
        let back = try JSONDecoder().decode([QueryEntry].self, from: data)
        #expect(back == [original])
    }

    @Test func clientDisplayNamePrefersNameThenIp() throws {
        let named = try decode(#"{"id":"1","timestamp":"2026-05-25T12:30:45","domain":"d","client_ip":"10.0.0.2","client_name":"tv","status":"CACHE"}"#)
        let blankName = try decode(#"{"id":"1","timestamp":"2026-05-25T12:30:45","domain":"d","client_ip":"10.0.0.2","client_name":"","status":"CACHE"}"#)
        #expect(named.clientDisplayName == "tv")
        #expect(blankName.clientDisplayName == "10.0.0.2")
    }
}

// MARK: - Status classification

struct QueryStatusKindTests {
    @Test func piholeV6DenyAndUpstreamStatusesAreBlocked() {
        for status in ["DENYLIST", "DENYLIST_CNAME", "EXTERNAL_BLOCKED_NXRA",
                       "EXTERNAL_BLOCKED_EDE15", "SPECIAL_DOMAIN"] {
            #expect(QueryStatusKind(status: status) == .blocked, "expected \(status) blocked")
        }
    }

    @Test func classifiesTheRemainingKinds() {
        #expect(QueryStatusKind(status: "CACHE_STALE") == .cached)
        #expect(QueryStatusKind(status: "FORWARDED") == .permitted)
        #expect(QueryStatusKind(status: "RETRIED_DNSSEC") == .permitted)
        #expect(QueryStatusKind(status: "IN_PROGRESS") == .other)
        #expect(QueryStatusKind(status: "") == .other)
        #expect(QueryStatusKind(status: "gravity") == .blocked) // case-insensitive
    }

    @Test func everyBlockedStatusHasAnExplanation() {
        for status in QueryStatusKind.blockedStatuses {
            #expect(QueryGlossary.statusExplanation(status) != nil, "no explanation for \(status)")
        }
        #expect(QueryGlossary.statusExplanation("SOMETHING_NEW") == nil)
    }

    @Test func glossaryCoversCommonTypes() {
        #expect(QueryGlossary.queryTypeExplanation("aaaa") == "IPv6 address")
        #expect(QueryGlossary.replyTypeExplanation("NXDOMAIN") != nil)
        #expect(QueryGlossary.queryTypeExplanation("TYPE65000") == nil)
    }
}

// MARK: - URL building

/// Domains in the query log are whatever a device on the network looked up,
/// so they're untrusted when placed into a request path.
struct APIClientURLBuildingTests {
    @Test func ordinaryDomainsPassThrough() {
        #expect(APIClient.domainPathSegment("ads.example.com") == "ads.example.com")
        #expect(APIClient.domainPathSegment("  Ads.Example.COM ") == "ads.example.com")
        #expect(APIClient.domainPathSegment("_dmarc.example.com") == "_dmarc.example.com")
    }

    @Test func wildcardIsEncodedNotPassedRaw() {
        #expect(APIClient.domainPathSegment("*.example.com") == "%2A.example.com")
    }

    @Test func rejectsAnythingThatCouldLeaveThePathSegment() {
        for bad in ["", "..", ".", "a/b", "../../sync", "a?b=c", "a#b", "a b",
                    "a%2fb", "exämple.com", "a\\b", "a:b", "a@b"] {
            #expect(APIClient.domainPathSegment(bad) == nil, "expected \(bad) rejected")
        }
        #expect(APIClient.domainPathSegment(String(repeating: "a", count: 254)) == nil)
    }

    @Test func queryValuesCannotAddParameters() {
        #expect(APIClient.queryValue("a&blocked=false") == "a%26blocked%3Dfalse")
        #expect(APIClient.queryValue("a+b c#d") == "a%2Bb%20c%23d")
        #expect(APIClient.queryValue("10.0.1.50") == "10.0.1.50")
        #expect(APIClient.queryValue("   ") == nil)
        #expect(APIClient.queryValue(nil) == nil)
    }
}

// MARK: - Demo data

struct DemoDataQueryDetailTests {
    private func page(filter: QueryFilter = .all, domain: String? = nil, client: String? = nil) -> QueryPage {
        DemoData.queries(page: 1, pageSize: 500, range: .today, filter: filter, domain: domain, client: client)
    }

    @Test func domainFilterMatchesSubstring() {
        let items = page(domain: "apple").items
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.domain.contains("apple") })
    }

    @Test func clientFilterMatchesIpOrName() {
        let byIp = page(client: "10.0.1.50").items
        let byName = page(client: "kitchen").items
        #expect(!byIp.isEmpty)
        #expect(byIp.allSatisfy { $0.clientIp == "10.0.1.50" })
        #expect(!byName.isEmpty)
        #expect(byName.allSatisfy { $0.clientName == "Kitchen-iPad" })
    }

    @Test func blockedAndPermittedFiltersPartitionTheLog() {
        let all = page().total
        let blocked = page(filter: .blocked)
        let permitted = page(filter: .permitted)
        let allBlocked = blocked.items.allSatisfy { $0.isBlocked }
        let nonePermittedBlocked = permitted.items.allSatisfy { !$0.isBlocked }
        #expect(allBlocked)
        #expect(nonePermittedBlocked)
        #expect(blocked.total + permitted.total == all)
        #expect(blocked.total > 0)
    }

    @Test func rowsCarryDetailFields() {
        let items = page().items
        #expect(items.allSatisfy { $0.queryType != nil && $0.replyType != nil && $0.replyTimeMs != nil })
    }

    @Test func blockedDemoDomainsNameTheListThatBlocksThem() {
        let lists = DemoData.domainBlocklists("doubleclick.net")
        #expect(!lists.lists.isEmpty)
        #expect(lists.blockCount > 0)
        #expect(DemoData.domainBlocklists("apple.com").lists.isEmpty)
        #expect(DemoData.domainStatus("ads.youtube.com").effective == "denied")
        #expect(DemoData.domainStatus("apple.com").effective == "unmanaged")
    }
}

// MARK: - Domain list decoding

struct DomainListDecodingTests {
    @Test func decodesStatus() throws {
        let json = #"{"domain":"ads.example.com","in_deny":true,"in_allow":false,"effective":"denied"}"#
        let status = try makeAPIDecoder().decode(DomainListStatus.self, from: Data(json.utf8))
        #expect(status.inDeny)
        #expect(!status.inAllow)
        #expect(status.effective == "denied")
    }

    @Test func decodesBlocklistsWithDefaults() throws {
        let json = """
        {"domain":"ads.example.com","block_count":7,"lists":[
          {"name":"HaGeZi Pro","address":"https://example.org/pro.txt","kind":"gravity","enabled":true,"is_security":true},
          {"name":"ads.example.com","address":null,"kind":"deny-exact"}
        ]}
        """
        let lists = try makeAPIDecoder().decode(DomainBlocklists.self, from: Data(json.utf8))
        #expect(lists.blockCount == 7)
        #expect(lists.lists.count == 2)
        #expect(lists.lists[0].isSecurity)
        #expect(lists.lists[0].kindLabel == "Adlist")
        #expect(lists.lists[1].enabled)        // defaulted
        #expect(!lists.lists[1].isSecurity)    // defaulted
        #expect(lists.lists[1].address == nil)
    }
}

// MARK: - View model

@MainActor
struct QueryLogViewModelTests {
    private func makeVM() -> QueryLogViewModel {
        let site = Site(
            name: "Demo",
            baseURL: URL(string: "https://demo.mypi.invalid")!,
            isDemo: true
        )
        return QueryLogViewModel(client: APIClient(site: site))
    }

    /// Filter changes reset on a follow-up task; poll until it lands.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func loadInitialPopulatesRowsAndTotal() async {
        let vm = makeVM()
        await vm.loadInitial()
        #expect(!vm.queries.isEmpty)
        #expect(vm.totalCount == 120)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
        #expect(Set(vm.queries.map(\.id)).count == vm.queries.count)
    }

    @Test func showQueriesForDomainNarrowsServerSide() async {
        let vm = makeVM()
        await vm.loadInitial()
        vm.showQueries(forDomain: "github.com")
        await waitUntil { vm.totalCount != 120 && !vm.isLoading }
        #expect(vm.domainFilter == "github.com")
        #expect(!vm.queries.isEmpty)
        #expect(vm.queries.allSatisfy { $0.domain == "github.com" })

        vm.domainFilter = nil
        await waitUntil { vm.totalCount == 120 && !vm.isLoading }
        #expect(vm.totalCount == 120)
    }

    @Test func showQueriesForClientLeavesUniqueClientsMode() async {
        let vm = makeVM()
        vm.filter = .uniqueClients
        await waitUntil { !vm.clients.isEmpty && !vm.isLoading }
        #expect(vm.isClientsMode)

        vm.showQueries(forClient: "10.0.1.20")
        await waitUntil { !vm.queries.isEmpty && !vm.isLoading }
        #expect(!vm.isClientsMode)
        #expect(vm.clientFilter == "10.0.1.20")
        #expect(vm.queries.allSatisfy { $0.clientIp == "10.0.1.20" })
        #expect(vm.clients.isEmpty)
    }

    @Test func blankDrillDownValuesAreIgnored() {
        let vm = makeVM()
        vm.showQueries(forDomain: "   ")
        vm.showQueries(forClient: "")
        #expect(vm.domainFilter == nil)
        #expect(vm.clientFilter == nil)
    }
}

// MARK: - Formatting

@MainActor
struct QueryDetailFormattingTests {
    @Test func replyTimeHidesMissingOrNegativeValues() {
        #expect(QueryDetailView.replyTimeText(nil) == nil)
        #expect(QueryDetailView.replyTimeText(-1) == nil)
        #expect(QueryDetailView.replyTimeText(.nan) == nil)
        #expect(QueryDetailView.replyTimeText(12.34)?.hasSuffix(" ms") == true)
        #expect(QueryDetailView.replyTimeText(2500)?.hasSuffix(" s") == true)
    }

    @Test func listSummaryMatchesTheWebDialogRules() {
        func status(deny: Bool, allow: Bool, effective: String) -> DomainListStatus {
            DomainListStatus(domain: "d", inDeny: deny, inAllow: allow, effective: effective)
        }
        #expect(QueryDetailView.listSummary(status: status(deny: true, allow: true, effective: "allowed"), queryBlocked: true).contains("both lists"))
        #expect(QueryDetailView.listSummary(status: status(deny: true, allow: false, effective: "denied"), queryBlocked: true).hasPrefix("Blocked"))
        #expect(QueryDetailView.listSummary(status: status(deny: false, allow: true, effective: "allowed"), queryBlocked: false).hasPrefix("Allowed"))
        #expect(QueryDetailView.listSummary(status: status(deny: false, allow: false, effective: "unmanaged"), queryBlocked: true).contains("adlist"))
    }
}

// MARK: - Hardening

struct HardeningTests {
    @Test func longServerErrorTextIsCapped() {
        let long = APIError(detail: String(repeating: "x", count: 5_000))
        let shown = ErrorMessage.userFacing(long)
        #expect(shown.count == ErrorMessage.maxDetailLength + 1)
        #expect(shown.hasSuffix("…"))
        #expect(ErrorMessage.userFacing(APIError(detail: "  ")) == "The server reported an error.")
    }

    @Test func slugIsConfinedToItsPathSegment() {
        let client = APIClient(site: Site(
            name: "T",
            baseURL: URL(string: "https://pi.example.com")!,
            mypiSiteSlug: "cabin/../x?y"
        ))
        #expect(client.resolvedPath("/api/queries") == "/api/sites/cabin%2F..%2Fx%3Fy/queries")
    }

    @Test func demoQueryLogPagesLikeTheServer() {
        func page(_ n: Int) -> QueryPage {
            DemoData.queries(page: n, pageSize: 50, range: .today, filter: .all, domain: nil)
        }
        #expect(page(1).items.count == 50)
        #expect(page(3).items.count == 20)
        #expect(page(4).items.isEmpty)
        #expect(page(2).total == 120)
        let ids = (1...3).flatMap { page($0).items.map(\.id) }
        #expect(Set(ids).count == 120)
    }
}
