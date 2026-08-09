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

    func test_start_sendsNonEmptyClientId() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        let data = Data((mock.lastConfigJSON ?? "").utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse((json["clientId"] as? String ?? "").isEmpty)
        pm.stop()
    }

    // MARK: – stop

    func test_stop_resetsFlags() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.stop()
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.connectedStreams, 0)
        XCTAssertEqual(pm.totalStreams, 0)
        XCTAssertTrue(mock.stopCalled)
    }

    // MARK: – Авто-реконнект
    //
    // Состояние теперь push-driven (EventSinkBridge.onState → ProxyManager.
    // handleState), поэтому тесты дёргают handleState напрямую вместо того,
    // чтобы выставлять mock.currentState и ждать поллинг-таймер.

    func test_autoReconnect_connectedThenError_entersRetryBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertEqual(mock.startCallCount, 1)

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        XCTAssertEqual(pm.state, .connected)

        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")

        XCTAssertEqual(pm.state, .retryBackoff)
        XCTAssertTrue(pm.isRunning, "isRunning должен оставаться true, чтобы UI показывал кнопку «Отключиться»")
        XCTAssertGreaterThan(pm.retryBackoffSeconds, 0, "Первый бекофф ~1с")
        XCTAssertLessThanOrEqual(pm.retryBackoffSeconds, 1)
        pm.stop()
    }

    func test_autoReconnect_connectingThenError_doesNotRetry() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        // connected мы НЕ увидели → everConnected остаётся false.
        pm.handleState("connecting", streams: 0, total: 1, errMsg: "")
        XCTAssertEqual(pm.state, .connecting)

        let startsBefore = mock.startCallCount
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(mock.startCallCount, startsBefore, "Не должно быть авто-ретраев без предыдущего connected")
        XCTAssertNotEqual(pm.state, .retryBackoff)
        pm.stop()
    }

    func test_autoReconnect_stop_cancelsBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        let restartsBefore = mock.restartCallCount
        pm.stop()

        // Ждём дольше первого бекоффа — никакого рестарта случиться не должно.
        try? await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(mock.restartCallCount, restartsBefore, "Stop должен отменить цепочку ретраев")
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.retryBackoffSeconds, 0)
    }

    func test_autoReconnect_performsRestart_afterBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        let restartsBefore = mock.restartCallCount

        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        // Ждём пока выполнится первый ретрай (бекофф ~1с).
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline, mock.restartCallCount == restartsBefore {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(mock.restartCallCount, restartsBefore,
                             "После бекоффа должен быть выполнен mobile.restart")
        pm.stop()
    }

    func test_autoReconnect_recovered_returnsToConnected() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        // Полный цикл: connected → error → бекофф → опять connected (пуш от
        // ядра после того, как реконнект в фоне отработал).
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        XCTAssertEqual(pm.state, .connected)
        XCTAssertTrue(pm.isRunning)
        pm.stop()
    }
}
