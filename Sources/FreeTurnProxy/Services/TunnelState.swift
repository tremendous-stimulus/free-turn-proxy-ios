import Foundation

enum TunnelState: String, Equatable {
    case idle = "idle"
    case connecting = "connecting"
    case connected = "connected"
    case captcha = "captcha"
    case error = "error"
    // Swift-only состояние: ждём паузу бекоффа перед очередным авто-ретраем.
    // Go про него не знает — выставляется в ProxyManager.
    case retryBackoff = "retry_backoff"
    // Swift-only: путь сети unsatisfied во время активной сессии (план,
    // фаза 2.4). Отдельно от retryBackoff — попытки реконнекта тут не
    // тратятся вообще, ждём появления пути.
    case waitingNetwork = "waiting_network"

    init(goState: String) {
        self = TunnelState(rawValue: goState) ?? .idle
    }
}
