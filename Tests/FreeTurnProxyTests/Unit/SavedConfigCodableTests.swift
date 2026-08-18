import XCTest
@testable import FreeTurnProxy

final class SavedConfigCodableTests: XCTestCase {

    // Записи, сохранённые до Этапа B, не содержат новых полей вовсе.
    private func legacyJSON(obfKey: String) -> Data {
        Data("""
        {"id":"9E1A1B2C-1234-4A5B-8C9D-000000000001","name":"old","peer":"1.2.3.4:5",
         "obfKey":"\(obfKey)","dns":"","listen":"","transport":"tcp","manualCaptcha":false}
        """.utf8)
    }

    func test_decodeLegacyRecord_withObfKey_defaultsProfileToRtpopus() throws {
        let key = String(repeating: "a", count: 64)
        let cfg = try JSONDecoder().decode(SavedConfig.self, from: legacyJSON(obfKey: key))
        XCTAssertEqual(cfg.obfProfile, "rtpopus", "иначе обфускация у существующих пользователей молча отключится")
        XCTAssertEqual(cfg.obfKey, key)
    }

    func test_decodeLegacyRecord_withoutObfKey_defaultsProfileToNone() throws {
        let cfg = try JSONDecoder().decode(SavedConfig.self, from: legacyJSON(obfKey: ""))
        XCTAssertEqual(cfg.obfProfile, "none")
    }

    func test_decodeLegacyRecord_newFieldsGetDefaults() throws {
        let cfg = try JSONDecoder().decode(SavedConfig.self, from: legacyJSON(obfKey: ""))
        XCTAssertEqual(cfg.mode, "udp")
        XCTAssertFalse(cfg.bond)
        XCTAssertEqual(cfg.threads, 0)
        XCTAssertEqual(cfg.streamsPerCred, 0)
        XCTAssertEqual(cfg.dnsMode, "auto")
        XCTAssertEqual(cfg.turnHost, "")
        XCTAssertEqual(cfg.turnPort, "")
        XCTAssertFalse(cfg.debug)
        XCTAssertEqual(cfg.clientId, "")
    }

    func test_roundTrip_preservesExplicitObfProfile() throws {
        let original = SavedConfig(name: "n", peer: "1.2.3.4:5", obfKey: "", obfProfile: "rtpopus2")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedConfig.self, from: data)
        XCTAssertEqual(decoded.obfProfile, "rtpopus2")
    }

    func test_init_explicitObfProfile_overridesInference() {
        let c = SavedConfig(name: "n", peer: "1.2.3.4:5", obfKey: "", obfProfile: "rtpopus3")
        XCTAssertEqual(c.obfProfile, "rtpopus3")
    }

    func test_init_noObfKey_defaultsProfileNone() {
        let c = SavedConfig(name: "n", peer: "1.2.3.4:5")
        XCTAssertEqual(c.obfProfile, "none")
    }

    // MARK: – useLocalTunnel

    // Ключа useLocalTunnel в записи нет вовсе — значит профиль сохранён до
    // появления WG-in-WG, и обязан остаться в старом режиме. Дефолт true в
    // memberwise-инициализаторе — это для действительно новых профилей,
    // decodeIfPresent тут при отсутствии ключа обязан вернуть false.
    func test_decodeLegacyRecord_useLocalTunnel_defaultsToFalse() throws {
        let cfg = try JSONDecoder().decode(SavedConfig.self, from: legacyJSON(obfKey: ""))
        XCTAssertFalse(cfg.useLocalTunnel)
    }

    // Новый профиль (через init, а не декодер) — наоборот, сразу в WG-in-WG.
    func test_init_newProfile_useLocalTunnelDefaultsToTrue() {
        let c = SavedConfig(name: "n", peer: "1.2.3.4:5")
        XCTAssertTrue(c.useLocalTunnel)
    }

    // Явно сохранённое значение (не важно какое) должно уцелеть при round-trip.
    func test_roundTrip_preservesExplicitUseLocalTunnel() throws {
        let original = SavedConfig(name: "n", peer: "1.2.3.4:5", useLocalTunnel: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedConfig.self, from: data)
        XCTAssertFalse(decoded.useLocalTunnel)
    }
}
