import XCTest
@testable import FreeTurnProxy

@MainActor
final class LogsViewModelTests: XCTestCase {

    func test_clear_callsMobileClearLogs() {
        let mock = MockMobileAPI()
        let vm = LogsViewModel(mobile: mock)
        vm.clear()
        XCTAssertTrue(mock.clearLogsCalled)
    }

    func test_clear_resetsLogsString() {
        let mock = MockMobileAPI()
        let vm = LogsViewModel(mobile: mock)
        vm.clear()
        XCTAssertEqual(vm.logs, "")
    }
}
