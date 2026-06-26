import XCTest
@testable import FreeTurnProxy

final class CertExpiryBannerTests: XCTestCase {

    func test_dayWord_pluralization() {
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 1), "дня")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 2), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 4), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 5), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 10), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 11), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 12), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 21), "дня")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 22), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 31), "дня")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 100), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 101), "дня")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 111), "дней")
        XCTAssertEqual(CertExpiryBanner.dayWord(forDays: 121), "дня")
    }
}
