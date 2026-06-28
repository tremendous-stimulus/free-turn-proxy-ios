import Foundation
import Mobile
@testable import FreeTurnProxy

final class MockMobileAPI: MobileAPI {
    var startCalled = false
    var startCallCount = 0
    var stopCalled = false
    var stopCallCount = 0
    var clearLogsCalled = false
    var manualCaptchaSet: Bool?
    var captchaPresenterSet = false

    var startError: Error?
    var logsToReturn = ""

    // Текущий снепшот состояния, который вернёт getState(). Тесты подменяют его
    // по ходу теста, чтобы прогнать туннель через connecting→connected→error.
    var currentState: String = "idle"
    var currentErrMsg: String = ""

    func setManualCaptcha(_ on: Bool) { manualCaptchaSet = on }

    func start(link: String, peer: String, dns: String, listen: String,
               transport: String, obfKey: String, clientType: String) throws {
        startCalled = true
        startCallCount += 1
        if let err = startError { throw err }
    }

    func stop() {
        stopCalled = true
        stopCallCount += 1
    }

    func getState() -> MobileSnapshot? {
        let s = MobileSnapshot()
        s.state = currentState
        s.errMsg = currentErrMsg
        return s
    }

    func getLogs() -> String { logsToReturn }

    func clearLogs() { clearLogsCalled = true }

    func setCaptchaPresenter(_ p: MobileCaptchaPresenterProtocol?) { captchaPresenterSet = true }
}
