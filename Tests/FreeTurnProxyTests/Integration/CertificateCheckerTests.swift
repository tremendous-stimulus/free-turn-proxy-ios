import XCTest
@testable import FreeTurnProxy

final class CertificateCheckerTests: XCTestCase {

    // ExpirationDate в формате plist (XML).
    private func provision(expiration iso: String) -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ExpirationDate</key>
            <date>\(iso)</date>
        </dict>
        </plist>
        """
        // Имитация CMS-обёртки: добавим мусора по краям, как в реальном .mobileprovision.
        return Data("HEADER GARBAGE\n".utf8) + Data(xml.utf8) + Data("\nTRAILER".utf8)
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }

    func test_expirationIn5Days_returns5() {
        let data = provision(expiration: "2030-01-06T00:00:00Z")
        let now = date("2030-01-01T00:00:00Z")
        XCTAssertEqual(CertificateChecker.daysUntilExpiry(in: data, now: now), 5)
    }

    func test_expirationIn6Point3Days_ceilingTo7() {
        // 6 дней + ~7 часов
        let data = provision(expiration: "2030-01-07T07:12:00Z")
        let now = date("2030-01-01T00:00:00Z")
        XCTAssertEqual(CertificateChecker.daysUntilExpiry(in: data, now: now), 7)
    }

    func test_expirationInPast_returnsNil() {
        let data = provision(expiration: "2020-01-01T00:00:00Z")
        let now = date("2026-01-01T00:00:00Z")
        XCTAssertNil(CertificateChecker.daysUntilExpiry(in: data, now: now))
    }

    func test_missingXML_returnsNil() {
        XCTAssertNil(CertificateChecker.daysUntilExpiry(in: Data("nothing".utf8),
                                                       now: Date()))
    }

    func test_missingExpirationKey_returnsNil() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Foo</key><string>bar</string></dict></plist>
        """
        XCTAssertNil(CertificateChecker.daysUntilExpiry(in: Data(xml.utf8), now: Date()))
    }

    func test_lessThanOneDay_returns1() {
        // Меньше суток до истечения → ceil → 1.
        let data = provision(expiration: "2030-01-01T05:00:00Z")
        let now = date("2030-01-01T00:00:00Z")
        XCTAssertEqual(CertificateChecker.daysUntilExpiry(in: data, now: now), 1)
    }
}
