import XCTest
@testable import FreeTurnProxy

@MainActor
final class ProxyManagerTests: XCTestCase {

    private func manager() -> (ProxyManager, MockMobileAPI) {
        let mock = MockMobileAPI()
        return (ProxyManager(mobile: mock), mock)
    }

    private func sampleConfig() -> FreeTurnConfig {
        FreeTurnConfig(link: "https://vk.com/call/join/abc",
                       peer: "1.2.3.4:12345",
                       dns: "8.8.8.8",
                       listen: "127.0.0.1:9000")
    }

    // MARK: – start

    func test_start_noConfig_throwsNoConfig() {
        let (pm, _) = manager()
        XCTAssertThrowsError(try pm.start()) { err in
            XCTAssertEqual((err as? AppError), .noConfig)
        }
    }

    func test_start_withConfig_setsIsRunning() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertTrue(pm.isRunning)
        XCTAssertTrue(mock.startCalled)
        pm.stop()
    }

    func test_start_propagatesMobileError() {
        let (pm, mock) = manager()
        mock.startError = NSError(domain: "test", code: 99)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        XCTAssertThrowsError(try pm.start())
        XCTAssertFalse(pm.isRunning)
        pm.stop()
    }

    // MARK: – stop

    func test_stop_resetsFlags() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.stop()
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(pm.state, "idle")
        XCTAssertEqual(pm.connectedStreams, 0)
        XCTAssertEqual(pm.totalStreams, 0)
        XCTAssertTrue(mock.stopCalled)
    }
}
