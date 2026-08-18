import Foundation
import Mobile
@testable import FreeTurnProxy

final class MockMobileAPI: MobileAPI {
    var startCalled = false
    var startCallCount = 0
    var restartCallCount = 0
    var stopCalled = false
    var stopCallCount = 0
    var wakeCallCount = 0
    var clearLogsCalled = false
    var eventSinkSet: MobileEventSinkProtocol?
    var protectorSet: MobileProtectorProtocol?
    // Порядок важен: protect обязан быть установлен до start, иначе первые
    // сокеты ядра уйдут в туннель (план, фаза 5.1).
    var protectSetBeforeStart = false

    var startError: Error?
    var restartError: Error?
    var lastConfigJSON: String?

    // Байтовые счётчики, которые ProxyManager вычитывает поллингом
    // getState() для статистики трафика (стадия/стримы/ошибка теперь идут
    // через push EventSink, а не через getState()).
    var txTotal: Int64 = 0
    var rxTotal: Int64 = 0
    var txRate: Int64 = 0
    var rxRate: Int64 = 0

    func setProtect(_ p: MobileProtectorProtocol?) { protectorSet = p }

    func start(configJSON: String) throws {
        protectSetBeforeStart = protectorSet != nil
        startCalled = true
        startCallCount += 1
        lastConfigJSON = configJSON
        if let err = startError { throw err }
    }

    func restart(configJSON: String) throws {
        restartCallCount += 1
        lastConfigJSON = configJSON
        if let err = restartError { throw err }
    }

    func stop() {
        stopCalled = true
        stopCallCount += 1
    }

    func wake() {
        wakeCallCount += 1
    }

    func getState() -> MobileSnapshot? {
        let s = MobileSnapshot()
        s.txTotal = txTotal
        s.rxTotal = rxTotal
        s.txRate = txRate
        s.rxRate = rxRate
        return s
    }

    func dumpLogs() -> String { "" }

    func clearLogs() { clearLogsCalled = true }

    func setEventSink(_ s: MobileEventSinkProtocol?) { eventSinkSet = s }

    func validateConfig(_ json: String) -> String { "" }

    func version() -> String { "mock" }
}
