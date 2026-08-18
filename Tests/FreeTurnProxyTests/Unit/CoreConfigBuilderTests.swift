import XCTest
@testable import FreeTurnProxy

final class CoreConfigBuilderTests: XCTestCase {

    private func base(_ overrides: (inout SavedConfig) -> Void = { _ in }) -> SavedConfig {
        var c = SavedConfig(name: "test", peer: "1.2.3.4:5678")
        overrides(&c)
        return c
    }

    func test_build_usesSavedConfigClientId_whenNonEmpty() {
        let c = base { $0.clientId = "abc123" }
        let cc = CoreConfigBuilder.build(config: c, links: ["https://vk.com/call/join/x"])
        XCTAssertEqual(cc.clientId, "abc123")
    }

    func test_build_fallsBackToDeviceClientId_whenEmpty() {
        let c = base()
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.clientId, ClientIdentity.current)
        XCTAssertFalse(cc.clientId.isEmpty)
    }

    func test_build_mapsObfuscationFields() {
        let c = base {
            $0.obfProfile = "rtpopus3"
            $0.obfKey = "deadbeef"
            $0.obfTimingMs = 42
        }
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.obf.profile, "rtpopus3")
        XCTAssertEqual(cc.obf.key, "deadbeef")
        XCTAssertEqual(cc.obf.timingMs, 42)
    }

    func test_build_zeroThreadsAndStreamsPerCred_keepCoreDefaults() {
        let c = base()
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.turn.n, 10)
        XCTAssertEqual(cc.vk.streamsPerCred, 10)
    }

    func test_build_positiveThreadsAndStreamsPerCred_override() {
        let c = base {
            $0.threads = 20
            $0.streamsPerCred = 5
        }
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.turn.n, 20)
        XCTAssertEqual(cc.vk.streamsPerCred, 5)
    }

    func test_build_dns_commaSeparatedList_splitsAndTrims() {
        let c = base { $0.dns = "8.8.8.8, 1.1.1.1 ,9.9.9.9" }
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.dns.servers, ["8.8.8.8", "1.1.1.1", "9.9.9.9"])
    }

    func test_build_emptyDns_leavesServersEmpty() {
        let c = base()
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertTrue(cc.dns.servers.isEmpty)
    }

    func test_build_turnHostPort_setWhenNonEmpty() {
        let c = base {
            $0.turnHost = "turn.example.com"
            $0.turnPort = "56000"
        }
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertEqual(cc.turn.host, "turn.example.com")
        XCTAssertEqual(cc.turn.port, "56000")
    }

    func test_build_links_passedThrough() {
        let c = base()
        let links = ["https://vk.com/call/join/a", "https://vk.com/call/join/b"]
        let cc = CoreConfigBuilder.build(config: c, links: links)
        XCTAssertEqual(cc.vk.links, links)
    }

    func test_build_debugAndManualCaptcha_passedThrough() {
        let c = base {
            $0.debug = true
            $0.manualCaptcha = true
        }
        let cc = CoreConfigBuilder.build(config: c, links: [])
        XCTAssertTrue(cc.log.debug)
        XCTAssertTrue(cc.vk.manualCaptcha)
    }
}
