import XCTest
@testable import FreeTurnProxy

final class LocalTunnelProfileFactoryTests: XCTestCase {
    private let sampleConf = """
    [Interface]
    PrivateKey = iF6qxNe5FbBOEVoNW1Aq1u8qUXfLI9wYU5FRV9G6/2E=
    Address = 10.0.0.2/32
    DNS = 8.8.8.8, 8.8.4.4

    [Peer]
    PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
    Endpoint = 1.2.3.4:51820
    AllowedIPs = 0.0.0.0/0
    """

    func test_make_extractsAddressAndDNS() throws {
        let profile = try LocalTunnelProfileFactory.make(remoteConfText: sampleConf)
        XCTAssertEqual(profile.address, "10.0.0.2/32")
        XCTAssertEqual(profile.dns, "8.8.8.8, 8.8.4.4")
        XCTAssertEqual(profile.remoteConfText, sampleConf)
    }

    func test_make_generatesDistinctServerAndClientKeys() throws {
        let profile = try LocalTunnelProfileFactory.make(remoteConfText: sampleConf)
        XCTAssertNotEqual(profile.serverPrivateKey, profile.clientPrivateKey)
        XCTAssertNotEqual(profile.serverPublicKey, profile.clientPublicKey)
        XCTAssertFalse(profile.serverPrivateKey.isEmpty)
        XCTAssertFalse(profile.clientPrivateKey.isEmpty)
    }

    func test_make_missingAddress_throws() {
        let conf = """
        [Interface]
        PrivateKey = iF6qxNe5FbBOEVoNW1Aq1u8qUXfLI9wYU5FRV9G6/2E=

        [Peer]
        PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
        Endpoint = 1.2.3.4:51820
        AllowedIPs = 0.0.0.0/0
        """
        XCTAssertThrowsError(try LocalTunnelProfileFactory.make(remoteConfText: conf))
    }

    func test_make_missingDNS_defaultsToEmpty() throws {
        let conf = """
        [Interface]
        PrivateKey = iF6qxNe5FbBOEVoNW1Aq1u8qUXfLI9wYU5FRV9G6/2E=
        Address = 10.0.0.2/32

        [Peer]
        PublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=
        Endpoint = 1.2.3.4:51820
        AllowedIPs = 0.0.0.0/0
        """
        let profile = try LocalTunnelProfileFactory.make(remoteConfText: conf)
        XCTAssertEqual(profile.dns, "")
    }
}
