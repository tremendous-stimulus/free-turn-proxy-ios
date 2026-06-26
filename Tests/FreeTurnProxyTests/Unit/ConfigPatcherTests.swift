import XCTest
@testable import FreeTurnProxy

final class ConfigPatcherTests: XCTestCase {

    private let allowed = "0.0.0.0/0"
    private let endpoint = "127.0.0.1:9000"

    // MARK: – Endpoint

    func test_existingEndpoint_replaced() {
        let input = """
        [Interface]
        PrivateKey = abc

        [Peer]
        PublicKey = xyz
        Endpoint = 1.2.3.4:5678
        AllowedIPs = 0.0.0.0/0
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("Endpoint = 127.0.0.1:9000"))
        XCTAssertFalse(out.contains("1.2.3.4:5678"))
    }

    func test_missingEndpoint_appendedToPeer() {
        let input = """
        [Interface]
        PrivateKey = abc

        [Peer]
        PublicKey = xyz
        AllowedIPs = 0.0.0.0/0
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("Endpoint = 127.0.0.1:9000"))
    }

    // MARK: – AllowedIPs

    func test_existingAllowedIPs_replaced() {
        let input = """
        [Interface]

        [Peer]
        AllowedIPs = 10.0.0.0/8, 192.168.0.0/16
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("AllowedIPs = 0.0.0.0/0"))
        XCTAssertFalse(out.contains("10.0.0.0/8"))
    }

    func test_missingAllowedIPs_appended() {
        let input = """
        [Interface]

        [Peer]
        PublicKey = xyz
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("AllowedIPs = 0.0.0.0/0"))
    }

    // MARK: – MTU

    func test_missingMTU_appendedToInterface() {
        let input = """
        [Interface]
        PrivateKey = abc

        [Peer]
        PublicKey = xyz
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("MTU = 1280"))
    }

    func test_existingMTU_overwrittenTo1280() {
        let input = """
        [Interface]
        PrivateKey = abc
        MTU = 1420

        [Peer]
        PublicKey = xyz
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        XCTAssertTrue(out.contains("MTU = 1280"))
        XCTAssertFalse(out.contains("1420"))
    }

    // MARK: – AWG-ключи

    func test_awgObfuscationKeys_preserved() {
        let input = """
        [Interface]
        PrivateKey = abc
        Jc = 4
        Jmin = 50
        Jmax = 1000
        S1 = 100
        S2 = 100
        H1 = 1
        H2 = 2
        H3 = 3
        H4 = 4

        [Peer]
        PublicKey = xyz
        AllowedIPs = 0.0.0.0/0
        Endpoint = 1.2.3.4:5
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        for line in ["Jc = 4", "Jmin = 50", "Jmax = 1000",
                     "S1 = 100", "S2 = 100",
                     "H1 = 1", "H2 = 2", "H3 = 3", "H4 = 4"] {
            XCTAssertTrue(out.contains(line), "ключ \(line) должен сохраниться")
        }
    }

    // MARK: – Граничные

    func test_configWithoutPeer_doesNotCrashAndNoPeerKeys() {
        let input = """
        [Interface]
        PrivateKey = abc
        """
        let out = ConfigPatcher.patch(input, allowedIPs: allowed, endpoint: endpoint)
        // MTU должен быть дописан в [Interface]
        XCTAssertTrue(out.contains("MTU = 1280"))
        // Peer-ключей быть не должно — нет секции [Peer]
        XCTAssertFalse(out.contains("Endpoint ="))
        XCTAssertFalse(out.contains("AllowedIPs ="))
    }

    func test_emptyConfig_returnsAtLeastEmpty() {
        let out = ConfigPatcher.patch("", allowedIPs: allowed, endpoint: endpoint)
        XCTAssertFalse(out.contains("Endpoint"))
        XCTAssertFalse(out.contains("MTU"))
    }
}
