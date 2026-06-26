import XCTest
@testable import FreeTurnProxy

final class ErrorLoggerParseTests: XCTestCase {

    func test_parsesValidLine_INF() {
        let entry = ErrorLogger.parseGoLine("12:34:56 [INF] tunnel started")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, "INF")
        XCTAssertEqual(entry?.message, "tunnel started")
        XCTAssertTrue(entry?.display.hasSuffix("[INF] tunnel started") ?? false)
    }

    func test_parsesAllSupportedLevels() {
        for lvl in ["DBG", "INF", "WRN", "ERR"] {
            let entry = ErrorLogger.parseGoLine("01:02:03 [\(lvl)] hi")
            XCTAssertEqual(entry?.level, lvl)
        }
    }

    func test_utcISO_isUTCFormatted() {
        let entry = ErrorLogger.parseGoLine("00:00:00 [INF] start")
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.utcISO.hasSuffix("Z") || entry!.utcISO.contains("+0000"))
    }

    func test_rejectsUnknownLevel() {
        XCTAssertNil(ErrorLogger.parseGoLine("12:34:56 [FOO] message"))
        XCTAssertNil(ErrorLogger.parseGoLine("12:34:56 [warn] message"))
    }

    func test_rejectsJunk() {
        XCTAssertNil(ErrorLogger.parseGoLine(""))
        XCTAssertNil(ErrorLogger.parseGoLine("just some text"))
        XCTAssertNil(ErrorLogger.parseGoLine("[INF] no time"))
        XCTAssertNil(ErrorLogger.parseGoLine("12:34 [INF] short time"))
        XCTAssertNil(ErrorLogger.parseGoLine("12:34:56 INF no brackets"))
    }
}
