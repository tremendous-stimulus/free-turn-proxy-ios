import Foundation
import Mobile

// Приёмник событий ядра v2 (MobileEventSinkProtocol) — заменяет разбор текста
// логов и captcha-презентер из v1.8.0: стадия, счётчик стримов и captcha
// приходят готовыми значениями через push, а не поллингом.
//
// Контракт ядра (mobile/api.go):
//   - onState вызывается только на изменение и всегда из одной горутины;
//   - onLog может прийти из любой горутины ядра — реализация обязана быть
//     потокобезопасной;
//   - ни один метод не должен блокировать — они стоят на пути сессии.
// ErrorLogger и @Published-свойства ProxyManager документированы как
// «мутации только на Main thread», поэтому каждый метод уводит работу на main.
//
// Go не удерживает объект от GC — ссылка живёт в статике (тот же приём, что
// был у CaptchaPresenterBridge в v1.8.0).
final class EventSinkBridge: NSObject, MobileEventSinkProtocol {
    static let shared = EventSinkBridge()

    private override init() { super.init() }

    static func register(mobile: MobileAPI = LiveMobileAPI()) {
        mobile.setEventSink(shared)
        CaptchaController.shared.registerNotifications()
    }

    func onState(_ state: String?, streams: Int, total: Int, errMsg: String?) {
        DispatchQueue.main.async {
            ProxyManager.shared.handleState(state ?? "idle", streams: streams, total: total, errMsg: errMsg ?? "")
        }
    }

    func onLog(_ level: String?, msg: String?, unixMillis: Int64) {
        DispatchQueue.main.async {
            ErrorLogger.shared.ingest(level: level ?? "info", message: msg ?? "", unixMillis: unixMillis)
        }
    }

    // Пустой url — закрыть окно captcha.
    func onCaptcha(_ url: String?) {
        DispatchQueue.main.async {
            let url = url ?? ""
            if url.isEmpty {
                CaptchaController.shared.hide()
            } else {
                CaptchaController.shared.show(url)
            }
        }
    }
}
