import XCTest
@testable import FreeTurnProxy

final class LocalTunnelIdentityTests: XCTestCase {
    func test_generateKeyPair_producesValidBase64_32Bytes() {
        let pair = LocalTunnelIdentity.generateKeyPair()
        let priv = try? XCTUnwrap(Data(base64Encoded: pair.privateKeyBase64))
        let pub = try? XCTUnwrap(Data(base64Encoded: pair.publicKeyBase64))
        XCTAssertEqual(priv?.count, 32)
        XCTAssertEqual(pub?.count, 32)
    }

    func test_generateKeyPair_producesDistinctPairs() {
        let a = LocalTunnelIdentity.generateKeyPair()
        let b = LocalTunnelIdentity.generateKeyPair()
        XCTAssertNotEqual(a.privateKeyBase64, b.privateKeyBase64)
        XCTAssertNotEqual(a.publicKeyBase64, b.publicKeyBase64)
    }
}
