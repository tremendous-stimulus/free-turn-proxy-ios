import XCTest
@testable import FreeTurnProxy

// Ядро v3.1.0 декодирует ClientJSON с DisallowUnknownFields() (internal/config/json.go):
// лишнее или переименованное поле здесь ломает старт туннеля в рантайме, а не на
// сборке. Этот тест сверяет набор ключей нашего энкодера с полями схемы ядра —
// если кто-то переименует/добавит поле в CoreConfig не туда, тест упадёт раньше
// живого устройства.
final class CoreConfigTests: XCTestCase {

    private func keys(of json: [String: Any]) -> Set<String> { Set(json.keys) }

    private func decode(_ config: CoreConfig) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_topLevelKeys_matchClientJSONSchema() throws {
        let json = try decode(CoreConfig(peer: "1.2.3.4:56000", clientId: "abc"))
        XCTAssertEqual(keys(of: json), [
            "peer", "clientId", "subUrl", "provider", "routes",
            "turn", "proxy", "vk", "obf", "dns", "log", "tunnel",
        ])
    }

    func test_nestedKeys_matchClientJSONSchema() throws {
        let json = try decode(CoreConfig(peer: "1.2.3.4:56000", clientId: "abc"))
        XCTAssertEqual(keys(of: try XCTUnwrap(json["turn"] as? [String: Any])),
                       ["n", "transport", "host", "port"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["proxy"] as? [String: Any])),
                       ["listen"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["vk"] as? [String: Any])),
                       ["links", "streamsPerCred", "manualCaptcha", "platform"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["obf"] as? [String: Any])),
                       ["profile", "key", "timingMs"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["dns"] as? [String: Any])),
                       ["mode", "servers"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["log"] as? [String: Any])),
                       ["debug"])
        XCTAssertEqual(keys(of: try XCTUnwrap(json["tunnel"] as? [String: Any])),
                       ["mode", "config", "mtu"])
    }

    func test_clientId_alwaysNonEmpty() {
        XCTAssertFalse(ClientIdentity.current.isEmpty)
    }

    func test_defaults_satisfyCoreValidation() throws {
        // internal/config/validate.go: streamsPerCred > 0, platform desktop|mobile,
        // dns.mode валиден. Дефолты CoreConfig обязаны это соблюдать сами по себе —
        // ProxyManager их не переопределяет для streamsPerCred/platform/dns.mode.
        let json = try decode(CoreConfig(peer: "1.2.3.4:56000", clientId: "abc"))
        let vk = try XCTUnwrap(json["vk"] as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(vk["streamsPerCred"] as? Int), 0)
        XCTAssertEqual(vk["platform"] as? String, "mobile")
        let dns = try XCTUnwrap(json["dns"] as? [String: Any])
        XCTAssertEqual(dns["mode"] as? String, "auto")
    }
}
