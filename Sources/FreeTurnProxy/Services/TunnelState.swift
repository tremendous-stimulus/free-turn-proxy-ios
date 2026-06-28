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

    init(goState: String) {
        self = TunnelState(rawValue: goState) ?? .idle
    }
}
