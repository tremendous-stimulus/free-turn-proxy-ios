import XCTest
@testable import FreeTurnProxy

final class UpdateCheckerTests: XCTestCase {

    func test_isNewer_basic() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.3", than: "1.2.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.2", than: "1.2.3"))
    }

    func test_isNewer_equal_isFalse() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2.3", than: "1.2.3"))
        XCTAssertFalse(UpdateChecker.isNewer("0.0.0", than: "0.0.0"))
    }

    func test_isNewer_numericCompare_not_lexical() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.9", than: "1.10.0"))
    }

    func test_isNewer_missingTrailingComponentIsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
    }

    func test_isNewer_majorBump() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }
}
