import XCTest
@testable import FreeTurnProxy

final class LocalConfigBuilderTests: XCTestCase {
    private func sampleLocal(port: Int = 9001) -> LocalWGConfig {
        LocalWGConfig(
            name: "freeturn-test", port: port,
            serverPrivateKey: "serverPriv", serverPublicKey: "serverPub",
            clientPrivateKey: "clientPriv", clientPublicKey: "clientPub",
            createdAt: Date()
        )
    }

    private func sampleExternal(dns: String = "8.8.8.8") -> ExternalWGConfig {
        ExternalWGConfig(
            remoteConfText: "irrelevant", address: "10.0.0.2/32", dns: dns,
            remoteEndpoint: "1.2.3.4:51820", createdAt: Date(), sentAt: nil
        )
    }

    func test_build_containsClientKeyAndServerPublicKey() {
        let text = LocalConfigBuilder.build(local: sampleLocal(), external: sampleExternal(), allowedIPs: "0.0.0.0/1, 128.0.0.0/1")
        XCTAssertTrue(text.contains("PrivateKey = clientPriv"))
        XCTAssertTrue(text.contains("PublicKey = serverPub"))
        XCTAssertFalse(text.contains("serverPriv"), "приватный ключ responder'а не должен уходить в AmneziaWG")
    }

    func test_build_usesResponderPortAndAddress() {
        let text = LocalConfigBuilder.build(local: sampleLocal(port: 9001), external: sampleExternal(), allowedIPs: "0.0.0.0/0")
        XCTAssertTrue(text.contains("Endpoint = 127.0.0.1:9001"))
        XCTAssertTrue(text.contains("Address = 10.0.0.2/32"))
        XCTAssertTrue(text.contains("MTU = 1280"))
        XCTAssertTrue(text.contains("AllowedIPs = 0.0.0.0/0"))
    }

    func test_build_usesConfiguredPort() {
        let text = LocalConfigBuilder.build(local: sampleLocal(port: 51821), external: sampleExternal(), allowedIPs: "0.0.0.0/0")
        XCTAssertTrue(text.contains("Endpoint = 127.0.0.1:51821"))
    }

    func test_build_emptyDNS_omitsDNSLine() {
        let text = LocalConfigBuilder.build(local: sampleLocal(), external: sampleExternal(dns: ""), allowedIPs: "0.0.0.0/0")
        XCTAssertFalse(text.contains("DNS ="))
    }
}
