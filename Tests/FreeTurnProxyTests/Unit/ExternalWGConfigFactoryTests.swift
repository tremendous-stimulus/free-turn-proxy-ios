import XCTest
@testable import FreeTurnProxy

final class ExternalWGConfigFactoryTests: XCTestCase {
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
        let config = try ExternalWGConfigFactory.make(remoteConfText: sampleConf)
        XCTAssertEqual(config.address, "10.0.0.2/32")
        XCTAssertEqual(config.dns, "8.8.8.8, 8.8.4.4")
        XCTAssertEqual(config.remoteConfText, sampleConf)
    }

    func test_make_extractsEndpoint() throws {
        let config = try ExternalWGConfigFactory.make(remoteConfText: sampleConf)
        XCTAssertEqual(config.remoteEndpoint, "1.2.3.4:51820")
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
        XCTAssertThrowsError(try ExternalWGConfigFactory.make(remoteConfText: conf))
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
        let config = try ExternalWGConfigFactory.make(remoteConfText: conf)
        XCTAssertEqual(config.dns, "")
    }
}
