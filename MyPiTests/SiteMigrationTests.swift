import Foundation
import Testing
@testable import MyPi

/// Site.init(from:) carries several back-compat / self-heal paths that have
/// each fixed a real shipped bug. These tests pin those paths so a future
/// refactor doesn't silently regress them.
struct SiteMigrationTests {
    @Test func legacyJSONWithoutIsDemoDefaultsToFalse() throws {
        // sites.json written by 0.1.5 and earlier didn't include `isDemo`.
        // Decoding such a row must treat it as a real (non-demo) site.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Old",
          "baseURL": "https://pi.example.com",
          "allowSelfSigned": false,
          "sortOrder": 0
        }
        """
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        #expect(site.isDemo == false)
        #expect(site.mypiSiteSlug == nil)
        #expect(site.mypiSiteName == nil)
    }

    @Test func demoHostSelfHealsIsDemoEvenWhenJSONSaysFalse() throws {
        // The 0.1.6 demo-mode bug wrote demo sites to disk with isDemo=false.
        // On load, any site pointing at the canonical RFC 2606 .invalid host
        // must be forced back to demo so APIClient short-circuits to DemoData
        // instead of trying to hit a name that can never resolve.
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Demo",
          "baseURL": "https://demo.mypi.invalid",
          "allowSelfSigned": false,
          "sortOrder": 0,
          "isDemo": false
        }
        """
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        #expect(site.isDemo == true)
    }

    @Test func demoHostMatchIsCaseInsensitive() throws {
        // URL hosts are canonically lowercase but URLs can be entered with
        // any casing. The self-heal must still kick in.
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Demo",
          "baseURL": "https://Demo.MyPi.Invalid",
          "allowSelfSigned": false,
          "sortOrder": 0,
          "isDemo": false
        }
        """
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        #expect(site.isDemo == true)
    }

    @Test func legacyJSONWithoutMypiSlugFieldsDefaultsToNil() throws {
        // sites.json from 0.1.x has neither mypiSiteSlug nor mypiSiteName.
        // Decoding must succeed with both as nil so the legacy `/api/...`
        // alias path is used (the contract for pre-multisite servers).
        let json = """
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "name": "Legacy",
          "baseURL": "https://pi.legacy.example.com",
          "allowSelfSigned": false,
          "sortOrder": 0,
          "isDemo": false
        }
        """
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        #expect(site.mypiSiteSlug == nil)
        #expect(site.mypiSiteName == nil)
    }

    @Test func mypiSlugFieldsRoundTrip() throws {
        // Once 0.2.0+ stamps slug/name onto a site, subsequent loads must
        // preserve them — this is what the 0.2.1 migration leaves behind
        // and the 0.2.2 view-identity fix keys off.
        let original = Site(
            name: "Multi",
            baseURL: URL(string: "https://multi.example.com")!,
            mypiSiteSlug: "cabin",
            mypiSiteName: "Cabin"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Site.self, from: data)
        #expect(decoded.mypiSiteSlug == "cabin")
        #expect(decoded.mypiSiteName == "Cabin")
    }
}
