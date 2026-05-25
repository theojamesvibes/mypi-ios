import Foundation
import Testing
@testable import MyPi

struct SiteModelTests {
    @Test func roundTripsAllFields() throws {
        let id = UUID()
        let site = Site(
            id: id,
            name: "Home",
            baseURL: URL(string: "https://pi.home.example.com")!,
            allowSelfSigned: true,
            pinnedCertFingerprint: "ABCD1234EF",
            sortOrder: 3
        )
        let data = try JSONEncoder().encode(site)
        let decoded = try JSONDecoder().decode(Site.self, from: data)
        #expect(decoded == site)
        #expect(decoded.id == id)
        #expect(decoded.pinnedCertFingerprint == "ABCD1234EF")
        #expect(decoded.sortOrder == 3)
        #expect(decoded.allowSelfSigned)
    }

    @Test func initDefaults() {
        let site = Site(name: "X", baseURL: URL(string: "https://x.example.com")!)
        #expect(site.allowSelfSigned == false)
        #expect(site.pinnedCertFingerprint == nil)
        #expect(site.sortOrder == 0)
    }
}
