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
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.connectedStreams, 0)
        XCTAssertEqual(pm.totalStreams, 0)
        XCTAssertTrue(mock.stopCalled)
    }

    // MARK: – Авто-реконнект

    // Polling-таймер тикает каждые 0.5с. Ждём кратные значения, чтобы успели
    // отработать переходы. Все ожидания в этих тестах <= 4с.
    private func waitUntil(_ cond: @escaping () -> Bool, timeout: TimeInterval = 3.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func test_autoReconnect_connectedThenError_entersRetryBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertEqual(mock.startCallCount, 1)

        // Симулируем connected — polling зафиксирует everConnected=true.
        mock.currentState = "connected"
        await waitUntil { pm.state == .connected }
        XCTAssertEqual(pm.state, .connected)

        // Теперь error — должен запустить триггер автоматического реконнекта.
        mock.currentState = "error"
        mock.currentErrMsg = "boom"
        await waitUntil { pm.state == .retryBackoff }

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
        mock.currentState = "connecting"
        await waitUntil { pm.state == .connecting }

        let startsBefore = mock.startCallCount
        mock.currentState = "error"
        await waitUntil { pm.state == .error || pm.state == .idle }
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(mock.startCallCount, startsBefore, "Не должно быть авто-ретраев без предыдущего connected")
        XCTAssertNotEqual(pm.state, .retryBackoff)
        pm.stop()
    }

    func test_autoReconnect_stop_cancelsBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        mock.currentState = "connected"
        await waitUntil { pm.state == .connected }
        mock.currentState = "error"
        await waitUntil { pm.state == .retryBackoff }

        let startsBefore = mock.startCallCount
        pm.stop()

        // Ждём дольше первого бекоффа — никаких новых start не должно произойти.
        try? await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(mock.startCallCount, startsBefore, "Stop должен отменить цепочку ретраев")
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.retryBackoffSeconds, 0)
    }

    func test_autoReconnect_performsRestart_afterBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        mock.currentState = "connected"
        await waitUntil { pm.state == .connected }
        let startsBefore = mock.startCallCount

        mock.currentState = "error"
        await waitUntil { pm.state == .retryBackoff }

        // Ждём пока выполнится первый ретрай (бекофф 1с + 0.6с пауза между stop/start).
        await waitUntil(timeout: 4.0) { mock.startCallCount > startsBefore }
        XCTAssertGreaterThan(mock.startCallCount, startsBefore,
                             "После бекоффа должен быть выполнен mobile.start заново")
        pm.stop()
    }

    func test_autoReconnect_recovered_returnsToConnected() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        // Полный цикл: connected → error → бекофф → опять connected.
        mock.currentState = "connected"
        await waitUntil { pm.state == .connected }

        mock.currentState = "error"
        await waitUntil { pm.state == .retryBackoff }

        // Имитируем что после ретрая туннель снова поднялся.
        mock.currentState = "connected"
        await waitUntil(timeout: 4.0) { pm.state == .connected }

        XCTAssertEqual(pm.state, .connected)
        XCTAssertTrue(pm.isRunning)
        pm.stop()
    }
}
