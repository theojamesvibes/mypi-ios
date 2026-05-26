import Foundation
import Testing
@testable import MyPi

/// `APIClient.resolvedPath` is the multi-site routing core: when a site has
/// a `mypiSiteSlug`, every `/api/...` request must be rewritten to
/// `/api/sites/{slug}/...` — except the two server-global endpoints
/// `/api/health` and `/api/sites`, which would produce nonsense paths
/// like `/api/sites/cabin/sites` if naively rewritten.
struct APIClientRoutingTests {
    private func client(slug: String?) -> APIClient {
        APIClient(site: Site(
            name: "T",
            baseURL: URL(string: "https://pi.example.com")!,
            mypiSiteSlug: slug
        ))
    }

    @Test func nilSlugLeavesPathsUnchanged() {
        let c = client(slug: nil)
        #expect(c.resolvedPath("/api/stats/summary?hours=1") == "/api/stats/summary?hours=1")
        #expect(c.resolvedPath("/api/health") == "/api/health")
        #expect(c.resolvedPath("/api/sites") == "/api/sites")
    }

    @Test func emptySlugIsTreatedAsNoSlug() {
        // The migration filter uses `mypiSiteSlug?.isEmpty ?? true` — empty
        // string and nil are both "no routing." Make sure resolvedPath agrees,
        // so a corrupt-but-present empty slug doesn't produce `/api//stats`.
        let c = client(slug: "")
        #expect(c.resolvedPath("/api/stats/summary") == "/api/stats/summary")
    }

    @Test func slugRewritesSiteScopedPaths() {
        let c = client(slug: "cabin")
        #expect(c.resolvedPath("/api/stats/summary?hours=1")
            == "/api/sites/cabin/stats/summary?hours=1")
        #expect(c.resolvedPath("/api/queries?page=1&page_size=50")
            == "/api/sites/cabin/queries?page=1&page_size=50")
        #expect(c.resolvedPath("/api/stats/history?since=…&bucket_minutes=5")
            == "/api/sites/cabin/stats/history?since=…&bucket_minutes=5")
        #expect(c.resolvedPath("/api/sync/status") == "/api/sites/cabin/sync/status")
    }

    @Test func slugDoesNotRewriteServerGlobalEndpoints() {
        // The footgun: rewriting these would produce paths the server can't
        // route (or worse, `/api/sites/cabin/sites` which silently returns
        // the wrong shape).
        let c = client(slug: "cabin")
        #expect(c.resolvedPath("/api/health") == "/api/health")
        #expect(c.resolvedPath("/api/sites") == "/api/sites")
    }

    @Test func slugDoesNotRewriteNonAPIPaths() {
        // Belt-and-braces — only `/api/` paths get the prefix treatment.
        let c = client(slug: "cabin")
        #expect(c.resolvedPath("/something/else") == "/something/else")
        #expect(c.resolvedPath("") == "")
    }
}
