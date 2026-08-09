import XCTest
@testable import FreeTurnProxy

final class FreeturnLinkTests: XCTestCase {

    private func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // Пример из docs/uri.md (апстрим internal/uri).
    private let exampleJSON = """
    {"v":1,"provider":"vk","peer":"1.2.3.4:56000","transport":"tcp","mode":"udp",
     "obf":"rtpopus","key":"d823fa","n":10,"cid":"a1b2c3","name":"RU-Server"}
    """

    func test_parse_referenceExampleFromUpstreamDocs() throws {
        let link = "freeturn://\(base64URL(exampleJSON))"
        let cfg = try FreeturnLink.parse(link, defaultName: "fallback")
        XCTAssertEqual(cfg.peer, "1.2.3.4:56000")
        XCTAssertEqual(cfg.transport, "tcp")
        XCTAssertEqual(cfg.mode, "udp")
        XCTAssertEqual(cfg.obfProfile, "rtpopus")
        XCTAssertEqual(cfg.obfKey, "d823fa")
        XCTAssertEqual(cfg.threads, 10)
        XCTAssertEqual(cfg.clientId, "a1b2c3")
        XCTAssertEqual(cfg.name, "RU-Server")
    }

    func test_parse_missingNameFallsBackToDefault() throws {
        let json = #"{"v":1,"provider":"vk","peer":"1.2.3.4:5"}"#
        let cfg = try FreeturnLink.parse("freeturn://\(base64URL(json))", defaultName: "fallback")
        XCTAssertEqual(cfg.name, "fallback")
        XCTAssertEqual(cfg.mode, "udp")
        XCTAssertEqual(cfg.transport, "udp")
        XCTAssertEqual(cfg.obfProfile, "none")
        XCTAssertEqual(cfg.dnsMode, "auto")
    }

    // Android кладёт нестандартное wg — не входит в схему v2.1.1, но должно
    // проходить разбор (лишние поля не ломают JSON-декодер), не влияя на SavedConfig.
    func test_parse_ignoresUnknownWgField() throws {
        let json = #"{"v":1,"provider":"vk","peer":"1.2.3.4:5","wg":"[Interface]\nPrivateKey = x"}"#
        let cfg = try FreeturnLink.parse("freeturn://\(base64URL(json))", defaultName: "fallback")
        XCTAssertEqual(cfg.peer, "1.2.3.4:5")
    }

    func test_parse_rejectsWrongScheme() {
        XCTAssertThrowsError(try FreeturnLink.parse("https://example.com", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .invalidScheme)
        }
    }

    func test_parse_rejectsEmptyPayload() {
        XCTAssertThrowsError(try FreeturnLink.parse("freeturn://", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .emptyPayload)
        }
    }

    func test_parse_rejectsUnsupportedVersion() {
        let json = #"{"v":2,"provider":"vk","peer":"1.2.3.4:5"}"#
        XCTAssertThrowsError(try FreeturnLink.parse("freeturn://\(base64URL(json))", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .unsupportedVersion)
        }
    }

    func test_parse_rejectsMissingProvider() {
        let json = #"{"v":1,"provider":"","peer":"1.2.3.4:5"}"#
        XCTAssertThrowsError(try FreeturnLink.parse("freeturn://\(base64URL(json))", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .missingProvider)
        }
    }

    func test_parse_rejectsMissingPeer() {
        let json = #"{"v":1,"provider":"vk","peer":""}"#
        XCTAssertThrowsError(try FreeturnLink.parse("freeturn://\(base64URL(json))", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .missingPeer)
        }
    }

    func test_parse_rejectsInvalidBase64() {
        XCTAssertThrowsError(try FreeturnLink.parse("freeturn://not!base64!", defaultName: "n")) { error in
            XCTAssertEqual(error as? FreeturnLinkError, .invalidBase64)
        }
    }

    // MARK: – Round-trip

    func test_encode_roundTripsThroughParse() throws {
        let original = SavedConfig(
            name: "n", peer: "5.6.7.8:9", obfKey: "abc123", transport: "tcp",
            obfProfile: "rtpopus2", mode: "tcp", bond: true, threads: 4, streamsPerCred: 2,
            dnsMode: "doh", turnHost: "", turnPort: "", debug: false
        )
        let link = FreeturnLink.encode(config: original, name: "n")
        XCTAssertTrue(link.hasPrefix("freeturn://"))
        let decoded = try FreeturnLink.parse(link, defaultName: "fallback")
        XCTAssertEqual(decoded.peer, original.peer)
        XCTAssertEqual(decoded.transport, original.transport)
        XCTAssertEqual(decoded.obfProfile, original.obfProfile)
        XCTAssertEqual(decoded.obfKey, original.obfKey)
        XCTAssertEqual(decoded.mode, original.mode)
        XCTAssertEqual(decoded.bond, original.bond)
        XCTAssertEqual(decoded.threads, original.threads)
        XCTAssertEqual(decoded.streamsPerCred, original.streamsPerCred)
        XCTAssertEqual(decoded.dnsMode, original.dnsMode)
        XCTAssertEqual(decoded.name, "n")
    }

    func test_encode_doesNotIncludeClientId() throws {
        var c = SavedConfig(name: "n", peer: "1.2.3.4:5")
        c.clientId = "shouldnotleak"
        let link = FreeturnLink.encode(config: c, name: "n")
        let decoded = try FreeturnLink.parse(link, defaultName: "fallback")
        XCTAssertEqual(decoded.clientId, "", "cid — механизм allowlist владельца сервера, свой clientId в исходящую ссылку не проставляем")
    }

    func test_encode_omitsKeyWhenProfileNone() throws {
        var c = SavedConfig(name: "n", peer: "1.2.3.4:5")
        c.obfProfile = "none"
        c.obfKey = "leftoverkey"
        let link = FreeturnLink.encode(config: c, name: "n")
        let decoded = try FreeturnLink.parse(link, defaultName: "fallback")
        XCTAssertEqual(decoded.obfKey, "")
    }
}
