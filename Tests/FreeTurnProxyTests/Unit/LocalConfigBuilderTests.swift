import XCTest
@testable import FreeTurnProxy

final class LocalConfigBuilderTests: XCTestCase {
    private func sampleProfile(dns: String = "8.8.8.8") -> LocalTunnelProfile {
        LocalTunnelProfile(
            id: UUID(),
            remoteConfText: "irrelevant",
            serverPrivateKey: "serverPriv",
            serverPublicKey: "serverPub",
            clientPrivateKey: "clientPriv",
            clientPublicKey: "clientPub",
            address: "10.0.0.2/32",
            dns: dns
        )
    }

    func test_build_containsClientKeyAndServerPublicKey() {
        let text = LocalConfigBuilder.build(profile: sampleProfile(), allowedIPs: "0.0.0.0/1, 128.0.0.0/1")
        XCTAssertTrue(text.contains("PrivateKey = clientPriv"))
        XCTAssertTrue(text.contains("PublicKey = serverPub"))
        XCTAssertFalse(text.contains("serverPriv"), "приватный ключ responder'а не должен уходить в AmneziaWG")
    }

    func test_build_usesResponderEndpointAndAddress() {
        let text = LocalConfigBuilder.build(profile: sampleProfile(), allowedIPs: "0.0.0.0/0")
        XCTAssertTrue(text.contains("Endpoint = 127.0.0.1:9000"))
        XCTAssertTrue(text.contains("Address = 10.0.0.2/32"))
        XCTAssertTrue(text.contains("MTU = 1280"))
        XCTAssertTrue(text.contains("AllowedIPs = 0.0.0.0/0"))
    }

    func test_build_emptyDNS_omitsDNSLine() {
        let text = LocalConfigBuilder.build(profile: sampleProfile(dns: ""), allowedIPs: "0.0.0.0/0")
        XCTAssertFalse(text.contains("DNS ="))
    }
}
