import Foundation
import Mobile

// Приёмник логов локального WG-in-WG модуля (golib/ftun). Только логи — в
// отличие от EventSinkBridge (ядро v2), ftun не публикует стадию/стримы
// push'ем: ProxyManager читает состояние через ftun.stats() тем же
// поллингом, что и байтовые счётчики Mobile.
final class FtunEventSinkBridge: NSObject, FtunEventSinkProtocol {
    static let shared = FtunEventSinkBridge()

    private override init() { super.init() }

    static func register(ftun: FtunAPI = LiveFtunAPI()) {
        ftun.setEventSink(shared)
    }

    private static let levelMap: [String: String] = ["verbose": "DBG", "error": "ERR"]

    func onLog(_ half: String?, level: String?, msg: String?) {
        let mapped = Self.levelMap[level ?? ""] ?? (level ?? "INF").uppercased()
        DispatchQueue.main.async {
            ErrorLogger.shared.appendAppLine(level: mapped, message: "[ftun] \(msg ?? "")")
        }
    }
}
