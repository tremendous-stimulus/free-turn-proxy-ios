import Foundation

enum TunnelState: String, Equatable {
    case idle = "idle"
    case connecting = "connecting"
    case connected = "connected"
    case captcha = "captcha"
    case error = "error"

    init(goState: String) {
        self = TunnelState(rawValue: goState) ?? .idle
    }
}
