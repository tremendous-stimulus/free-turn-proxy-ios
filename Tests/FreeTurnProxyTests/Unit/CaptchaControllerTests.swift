import XCTest
@testable import FreeTurnProxy

// CaptchaController — singleton, подчищаем состояние вокруг каждого теста.
// show()/hide() уводят мутации на главный поток через DispatchQueue.main.async,
// поэтому тесты асинхронные и ждут короткий Task.sleep, чтобы диспатч успел
// отработать (тот же приём, что в ErrorLoggerShipTests).
//
// Фактическая отправка пуша под captchaPushSent завязана на
// UIApplication.shared.applicationState != .active — в тестовом хосте
// приложение всегда активно, поэтому сам пуш здесь не проверяем (как и
// аналогичный shouldPostStatusPush() в ProxyManager — см. CLAUDE.md, ручная
// проверка на устройстве). Проверяем то, что не зависит от applicationState.
@MainActor
final class CaptchaControllerTests: XCTestCase {

    private let sut = CaptchaController.shared

    override func setUp() async throws {
        try await super.setUp()
        sut.hide()
        sut.resetPushSuppression()
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    override func tearDown() async throws {
        sut.hide()
        sut.resetPushSuppression()
        try? await Task.sleep(nanoseconds: 100_000_000)
        try await super.tearDown()
    }

    func test_show_setsPendingURLAndPresents() async throws {
        sut.show("https://example.com/captcha")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(sut.pendingURL, URL(string: "https://example.com/captcha"))
        XCTAssertTrue(sut.isPresented)
    }

    func test_hide_clearsPendingURL() async throws {
        sut.show("https://example.com/captcha")
        try? await Task.sleep(nanoseconds: 100_000_000)

        sut.hide()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(sut.pendingURL)
        XCTAssertFalse(sut.isPresented)
    }

    func test_reopen_withoutPendingURL_isNoOp() async throws {
        sut.reopen()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(sut.isPresented)
    }

    func test_reopen_withPendingURL_presents() async throws {
        sut.show("https://example.com/captcha")
        try? await Task.sleep(nanoseconds: 100_000_000)
        sut.isPresented = false

        sut.reopen()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(sut.isPresented)
    }

    func test_resetPushSuppression_clearsFlag() {
        // Прямая проверка сеттера, не завязанная на applicationState.
        sut.resetPushSuppression()
        XCTAssertFalse(sut.captchaPushSent)
    }
}
