import XCTest
@testable import FreeTurnProxy

final class FtunStartRequestTests: XCTestCase {
    func test_encodedJSON_matchesGoStartConfigKeys() throws {
        let req = FtunStartRequest(
            remoteConf: "conf-text",
            localPrivateKey: "priv",
            localPeerPublicKey: "pub",
            relayAddr: "127.0.0.1:9001",
            listenPort: 9000,
            mtu: 1280
        )
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: Data(req.encodedJSON().utf8)) as? [String: Any])
        // Ключи должны совпасть с json-тегами golib/ftun.StartConfig (device.go).
        XCTAssertEqual(json["remoteConf"] as? String, "conf-text")
        XCTAssertEqual(json["localPrivateKey"] as? String, "priv")
        XCTAssertEqual(json["localPeerPublicKey"] as? String, "pub")
        XCTAssertEqual(json["relayAddr"] as? String, "127.0.0.1:9001")
        XCTAssertEqual(json["listenPort"] as? Int, 9000)
        XCTAssertEqual(json["mtu"] as? Int, 1280)
    }
}
