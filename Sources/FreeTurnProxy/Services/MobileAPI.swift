import Foundation
import Mobile

// Прокладка над gomobile-биндингом (ядро v2.1.1, JSON-конфиг + push EventSink).
// Прод использует LiveMobileAPI; тесты — собственный мок. Сама логика по
// управлению туннелем остаётся в ProxyManager, MobileAPI лишь делает вызовы
// Go проверяемыми.
protocol MobileAPI {
    func start(configJSON: String) throws
    func restart(configJSON: String) throws
    func stop()
    func getState() -> MobileSnapshot?
    func dumpLogs() -> String
    func clearLogs()
    func setEventSink(_ s: MobileEventSinkProtocol?)
    func validateConfig(_ json: String) -> String
    func version() -> String
}

struct LiveMobileAPI: MobileAPI {
    func start(configJSON: String) throws {
        var err: NSError?
        MobileStart(configJSON, &err)
        if let err { throw err }
    }

    // tunFD всегда 0 — свой tunnel.mode wg/awg недоступен без энтайтлмента
    // packet-tunnel-provider, у нас tunnel.mode всегда "none".
    func restart(configJSON: String) throws {
        var err: NSError?
        MobileRestart(configJSON, 0, &err)
        if let err { throw err }
    }

    func stop() {
        MobileStop()
    }

    func getState() -> MobileSnapshot? {
        MobileGetState()
    }

    func dumpLogs() -> String {
        MobileDumpLogs()
    }

    func clearLogs() {
        MobileClearLogs()
    }

    func setEventSink(_ s: MobileEventSinkProtocol?) {
        MobileSetEventSink(s)
    }

    func validateConfig(_ json: String) -> String {
        MobileValidateConfig(json)
    }

    func version() -> String {
        MobileVersion()
    }
}
