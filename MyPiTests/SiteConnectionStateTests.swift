import Testing
@testable import MyPi

struct SiteConnectionStateTests {
    @Test func connectedExposesVersion() {
        let state = SiteConnectionState.connected(serverVersion: "2.0.10")
        #expect(state.isConnected)
        #expect(state.label == "Connected")
        #expect(state.detail == "2.0.10")
    }

    @Test func nonConnectedStatesAreNotConnected() {
        #expect(!SiteConnectionState.offline.isConnected)
        #expect(!SiteConnectionState.unknown.isConnected)
        #expect(!SiteConnectionState.probing.isConnected)
        #expect(!SiteConnectionState.unauthorized.isConnected)
    }

    @Test func detailIsPresentOnlyWhereMeaningful() {
        #expect(SiteConnectionState.unknown.detail == nil)
        #expect(SiteConnectionState.offline.detail == nil)
        #expect(SiteConnectionState.tlsError("handshake failed").detail == "handshake failed")
        #expect(SiteConnectionState.error("boom").detail == "boom")
    }

    @Test func labels() {
        #expect(SiteConnectionState.offline.label == "Offline")
        #expect(SiteConnectionState.unauthorized.label == "Unauthorized")
        #expect(SiteConnectionState.probing.label == "Connecting…")
        #expect(SiteConnectionState.tlsError("x").label == "TLS error")
    }
}
