import Testing
@testable import MyPi

struct MyPiTests {
    @Test func siteStoreRoundTrip() throws {
        // Basic smoke test: a Site can be encoded and decoded.
        let site = Site(
            name: "Test",
            baseURL: URL(string: "https://example.com")!,
            allowSelfSigned: false
        )
        let data = try JSONEncoder().encode([site])
        let decoded = try JSONDecoder().decode([Site].self, from: data)
        #expect(decoded.first?.name == "Test")
        #expect(decoded.first?.baseURL.absoluteString == "https://example.com")
    }
}
