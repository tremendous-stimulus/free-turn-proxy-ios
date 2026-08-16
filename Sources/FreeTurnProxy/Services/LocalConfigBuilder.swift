import Foundation

// Собирает текст локального .conf — того, что пользователь один раз
// заливает в AmneziaWG (план, фаза 2/3: «ставится один раз и навсегда»).
// Внутренний туннель ванильный WG без AmneziaWG-обфускации — он живёт на
// лупбэке, прятать его не от кого.
enum LocalConfigBuilder {
    static let responderEndpoint = "127.0.0.1:9000"
    static let mtu = 1280

    static func build(profile: LocalTunnelProfile, allowedIPs: String) -> String {
        var lines = [
            "[Interface]",
            "PrivateKey = \(profile.clientPrivateKey)",
            "Address = \(profile.address)",
        ]
        if !profile.dns.isEmpty {
            lines.append("DNS = \(profile.dns)")
        }
        lines.append("MTU = \(mtu)")
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(profile.serverPublicKey)")
        lines.append("Endpoint = \(responderEndpoint)")
        lines.append("AllowedIPs = \(allowedIPs)")
        return lines.joined(separator: "\n")
    }
}
