import Foundation
import Mobile

// Прокладка над gomobile-биндингом. Прод использует LiveMobileAPI; тесты —
// собственный мок. Сама логика по управлению туннелем остаётся в ProxyManager,
// MobileAPI лишь делает вызовы Go проверяемыми.
protocol MobileAPI {
    func setManualCaptcha(_ on: Bool)
    func start(link: String, peer: String, dns: String, listen: String,
               transport: String, obfKey: String, clientType: String) throws
    func stop()
    func getState() -> MobileSnapshot?
    func getLogs() -> String
    func clearLogs()
    func setCaptchaPresenter(_ p: MobileCaptchaPresenterProtocol?)
}

struct LiveMobileAPI: MobileAPI {
    func setManualCaptcha(_ on: Bool) {
        MobileSetManualCaptcha(on)
    }

    func start(link: String, peer: String, dns: String, listen: String,
               transport: String, obfKey: String, clientType: String) throws {
        var err: NSError?
        MobileStart(link, peer, dns, listen, transport, obfKey, clientType, &err)
        if let err { throw err }
    }

    func stop() {
        MobileStop()
    }

    func getState() -> MobileSnapshot? {
        MobileGetState()
    }

    func getLogs() -> String {
        MobileGetLogs()
    }

    func clearLogs() {
        MobileClearLogs()
    }

    func setCaptchaPresenter(_ p: MobileCaptchaPresenterProtocol?) {
        MobileSetCaptchaPresenter(p)
    }
}
