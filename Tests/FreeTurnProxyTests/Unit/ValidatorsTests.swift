import XCTest
@testable import FreeTurnProxy

final class ValidatorsTests: XCTestCase {

    // MARK: – endpoint

    func test_endpoint_acceptsIPv4WithPort() {
        XCTAssertTrue(Validators.endpoint("1.2.3.4:56000"))
        XCTAssertTrue(Validators.endpoint("127.0.0.1:9000"))
        XCTAssertTrue(Validators.endpoint("0.0.0.0:1"))
        XCTAssertTrue(Validators.endpoint("255.255.255.255:65535"))
    }

    func test_endpoint_acceptsDomainWithPort() {
        XCTAssertTrue(Validators.endpoint("example.com:443"))
        XCTAssertTrue(Validators.endpoint("api.vk.com:80"))
        XCTAssertTrue(Validators.endpoint("a.b.cc:1"))
    }

    func test_endpoint_rejectsMissingPort() {
        XCTAssertFalse(Validators.endpoint("1.2.3.4"))
        XCTAssertFalse(Validators.endpoint("example.com"))
        XCTAssertFalse(Validators.endpoint("1.2.3.4:"))
    }

    func test_endpoint_rejectsInvalidPort() {
        XCTAssertFalse(Validators.endpoint("1.2.3.4:0"))
        XCTAssertFalse(Validators.endpoint("1.2.3.4:65536"))
        XCTAssertFalse(Validators.endpoint("1.2.3.4:abc"))
        XCTAssertFalse(Validators.endpoint("1.2.3.4:-1"))
    }

    func test_endpoint_rejectsInvalidHost() {
        XCTAssertFalse(Validators.endpoint(":1234"))
        XCTAssertFalse(Validators.endpoint("999.999.999.999:80"))
        XCTAssertFalse(Validators.endpoint("not a host:80"))
    }

    func test_endpoint_doesNotSupportIPv6() {
        // Реализация по lastIndex(of: ":") — для IPv6 это означает, что
        // последний двоеточный сегмент трактуется как порт. Заведомо
        // не покрываем IPv6, фиксируем поведение.
        XCTAssertFalse(Validators.endpoint("[::1]:80"))
        XCTAssertFalse(Validators.endpoint("::1:80"))
    }

    // MARK: – ipv4

    func test_ipv4_acceptsNormal() {
        XCTAssertTrue(Validators.ipv4("8.8.8.8"))
        XCTAssertTrue(Validators.ipv4("0.0.0.0"))
        XCTAssertTrue(Validators.ipv4("255.255.255.255"))
        XCTAssertTrue(Validators.ipv4("192.168.1.1"))
    }

    func test_ipv4_rejectsLeadingZeros() {
        XCTAssertFalse(Validators.ipv4("01.2.3.4"))
        XCTAssertFalse(Validators.ipv4("1.02.3.4"))
    }

    func test_ipv4_rejectsOctetOutOfRange() {
        XCTAssertFalse(Validators.ipv4("256.1.1.1"))
        XCTAssertFalse(Validators.ipv4("1.1.1.300"))
    }

    func test_ipv4_rejectsWrongShape() {
        XCTAssertFalse(Validators.ipv4("1.2.3"))
        XCTAssertFalse(Validators.ipv4("1.2.3.4.5"))
        XCTAssertFalse(Validators.ipv4("a.b.c.d"))
        XCTAssertFalse(Validators.ipv4(""))
        XCTAssertFalse(Validators.ipv4("1..2.3"))
    }

    // MARK: – isHost

    func test_isHost_acceptsIPv4() {
        XCTAssertTrue(Validators.isHost("1.2.3.4"))
    }

    func test_isHost_acceptsDomain() {
        XCTAssertTrue(Validators.isHost("example.com"))
        XCTAssertTrue(Validators.isHost("api.vk.com"))
        XCTAssertTrue(Validators.isHost("a-b.c.io"))
    }

    func test_isHost_rejectsJunk() {
        XCTAssertFalse(Validators.isHost(""))
        XCTAssertFalse(Validators.isHost("no-tld"))
        XCTAssertFalse(Validators.isHost("space in name.com"))
        XCTAssertFalse(Validators.isHost(".com"))
    }

    // MARK: – hexKey

    func test_hexKey_accepts64HexLowercase() {
        let key = String(repeating: "a", count: 64)
        XCTAssertTrue(Validators.hexKey(key))
    }

    func test_hexKey_accepts64HexMixedCase() {
        let key = String(repeating: "aF0", count: 22) + "a9"  // 68 — заведомо неверный
        XCTAssertFalse(Validators.hexKey(key))
        let exactly64 = "deadBEEF" + String(repeating: "1234567890abcdef", count: 3) + "12345678"
        XCTAssertEqual(exactly64.count, 64)
        XCTAssertTrue(Validators.hexKey(exactly64))
    }

    func test_hexKey_rejectsShort() {
        XCTAssertFalse(Validators.hexKey(String(repeating: "a", count: 63)))
        XCTAssertFalse(Validators.hexKey(""))
    }

    func test_hexKey_rejectsNonHex() {
        let bad = String(repeating: "g", count: 64)
        XCTAssertFalse(Validators.hexKey(bad))
    }

    func test_hexKey_customLength() {
        XCTAssertTrue(Validators.hexKey("dead", length: 4))
        XCTAssertFalse(Validators.hexKey("dead", length: 5))
    }

    // MARK: – vkLink

    func test_vkLink_acceptsVKDomains() {
        XCTAssertTrue(Validators.vkLink("https://vk.com/call/join/abc"))
        XCTAssertTrue(Validators.vkLink("https://vk.ru/call/join/abc"))
        XCTAssertTrue(Validators.vkLink("https://m.vk.com/whatever"))
        XCTAssertTrue(Validators.vkLink("https://api.vk.ru/anything"))
    }

    func test_vkLink_rejectsHTTP() {
        XCTAssertFalse(Validators.vkLink("http://vk.com/call/join/abc"))
    }

    func test_vkLink_rejectsForeignDomains() {
        XCTAssertFalse(Validators.vkLink("https://vk.evil.com/x"))
        XCTAssertFalse(Validators.vkLink("https://notvk.com/x"))
        XCTAssertFalse(Validators.vkLink("https://example.com/x"))
    }

    func test_vkLink_rejectsJunk() {
        XCTAssertFalse(Validators.vkLink(""))
        XCTAssertFalse(Validators.vkLink("vk.com/call/join/abc"))
    }
}
