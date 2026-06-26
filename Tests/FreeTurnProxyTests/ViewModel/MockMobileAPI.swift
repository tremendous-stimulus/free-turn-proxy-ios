import Foundation
import Mobile
@testable import FreeTurnProxy

final class MockMobileAPI: MobileAPI {
    var startCalled = false
    var stopCalled = false
    var clearLogsCalled = false
    var manualCaptchaSet: Bool?
    var captchaPresenterSet = false

    var startError: Error?
    var logsToReturn = ""

    func setManualCaptcha(_ on: Bool) { manualCaptchaSet = on }

    func start(link: String, peer: String, dns: String, listen: String,
               transport: String, obfKey: String, clientType: String) throws {
        startCalled = true
        if let err = startError { throw err }
    }

    func stop() { stopCalled = true }

    func getState() -> MobileSnapshot? { nil }

    func getLogs() -> String { logsToReturn }

    func clearLogs() { clearLogsCalled = true }

    func setCaptchaPresenter(_ p: MobileCaptchaPresenterProtocol?) { captchaPresenterSet = true }
}
