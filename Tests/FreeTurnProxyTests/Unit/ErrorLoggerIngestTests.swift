import XCTest
@testable import FreeTurnProxy

@MainActor
final class ErrorLoggerIngestTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ErrorLogger.shared.clear()
    }

    override func tearDown() {
        ErrorLogger.shared.clear()
        super.tearDown()
    }

    func test_ingest_mapsLevels() {
        let cases: [(String, String)] = [
            ("debug", "DBG"), ("info", "INF"), ("warn", "WRN"), ("error", "ERR"),
        ]
        for (goLevel, expected) in cases {
            ErrorLogger.shared.clear()
            ErrorLogger.shared.ingest(level: goLevel, message: "hi", unixMillis: 0)
            XCTAssertEqual(ErrorLogger.shared.entries.first?.level, expected)
        }
    }

    func test_ingest_unknownLevel_passesThroughUppercased() {
        ErrorLogger.shared.ingest(level: "trace", message: "hi", unixMillis: 0)
        XCTAssertEqual(ErrorLogger.shared.entries.first?.level, "TRACE")
    }

    func test_ingest_preservesMessage() {
        ErrorLogger.shared.ingest(level: "info", message: "tunnel started", unixMillis: 0)
        XCTAssertEqual(ErrorLogger.shared.entries.first?.message, "tunnel started")
        XCTAssertTrue(ErrorLogger.shared.entries.first?.display.hasSuffix("[INF] tunnel started") ?? false)
    }

    func test_ingest_unixMillis_convertsToUTCISO() {
        // 2026-01-02T03:04:05Z
        let unixMillis: Int64 = 1_767_323_045_000
        ErrorLogger.shared.ingest(level: "info", message: "x", unixMillis: unixMillis)
        XCTAssertEqual(ErrorLogger.shared.entries.first?.utcISO, "2026-01-02T03:04:05Z")
    }

    func test_ingest_appendsInOrder() {
        ErrorLogger.shared.ingest(level: "info", message: "first", unixMillis: 0)
        ErrorLogger.shared.ingest(level: "warn", message: "second", unixMillis: 1000)
        XCTAssertEqual(ErrorLogger.shared.entries.map(\.message), ["first", "second"])
    }
}
