import XCTest
@testable import FreeTurnProxy

final class ConfigCodecTests: XCTestCase {

    func test_roundTrip_keepsFields() throws {
        let original = SavedConfig(
            name: "test",
            peer: "1.2.3.4:5678",
            obfKey: "deadbeef",
            dns: "8.8.8.8",
            listen: "127.0.0.1:9000",
            transport: "tcp"
        )
        let data = try ConfigCodec.encode(original)
        let parsed = try ConfigCodec.parse(data)
        XCTAssertEqual(parsed.name, original.name)
        XCTAssertEqual(parsed.peer, original.peer)
        XCTAssertEqual(parsed.obfKey, original.obfKey)
        XCTAssertEqual(parsed.dns, original.dns)
        XCTAssertEqual(parsed.listen, original.listen)
        XCTAssertEqual(parsed.transport, original.transport)
    }

    func test_parse_junk_throwsUnreadable() {
        let data = Data("это не JSON".utf8)
        XCTAssertThrowsError(try ConfigCodec.parse(data)) { err in
            XCTAssertTrue(err is ConfigCodecError)
        }
    }

    func test_parse_allEmptyFields_throws() {
        let data = Data(#"{"name":"", "peer":"", "obfKey":"", "dns":"", "listen":""}"#.utf8)
        XCTAssertThrowsError(try ConfigCodec.parse(data))
    }

    func test_parse_onlyPeer_isOK() throws {
        let data = Data(#"{"peer":"1.2.3.4:5678"}"#.utf8)
        let cfg = try ConfigCodec.parse(data)
        XCTAssertEqual(cfg.peer, "1.2.3.4:5678")
        XCTAssertEqual(cfg.name, "")
    }

    func test_parse_unknownFields_ignored() throws {
        let data = Data(#"{"peer":"1.2.3.4:5", "extra":"value", "future":42}"#.utf8)
        let cfg = try ConfigCodec.parse(data)
        XCTAssertEqual(cfg.peer, "1.2.3.4:5")
    }

    func test_parse_transport_normalised() throws {
        let tcp = try ConfigCodec.parse(Data(#"{"peer":"1.2.3.4:5", "transport":"TCP"}"#.utf8))
        XCTAssertEqual(tcp.transport, "tcp")

        let udp = try ConfigCodec.parse(Data(#"{"peer":"1.2.3.4:5", "transport":"udp"}"#.utf8))
        XCTAssertEqual(udp.transport, "udp")

        // Неизвестный → дефолт "udp"
        let weird = try ConfigCodec.parse(Data(#"{"peer":"1.2.3.4:5", "transport":"ftp"}"#.utf8))
        XCTAssertEqual(weird.transport, "udp")
    }

    func test_parse_trimsWhitespace() throws {
        let data = Data(#"{"peer":"  1.2.3.4:5  ", "name":"  ленивый ввод  "}"#.utf8)
        let cfg = try ConfigCodec.parse(data)
        XCTAssertEqual(cfg.peer, "1.2.3.4:5")
        XCTAssertEqual(cfg.name, "ленивый ввод")
    }
}
