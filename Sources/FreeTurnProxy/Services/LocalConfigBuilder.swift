import Foundation

// Собирает текст локального .conf — того, что пользователь один раз
// заливает в AmneziaWG (план, фаза 2/3: «ставится один раз и навсегда»).
// Внутренний туннель ванильный WG без AmneziaWG-обфускации — он живёт на
// лупбэке, прятать его не от кого.
enum LocalConfigBuilder {
    static let mtu = 1280

    // Забираем в туннель всё; исключения делает роутер ftun по адресу
    // назначения (план, фаза 5.2), а не список префиксов в файле.
    static let allowedIPsAll = "0.0.0.0/0"

    static func build(local: LocalWGConfig, external: ExternalWGConfig, allowedIPs: String) -> String {
        var lines = [
            "[Interface]",
            "PrivateKey = \(local.clientPrivateKey)",
            "Address = \(external.address)",
        ]
        if !external.dns.isEmpty {
            lines.append("DNS = \(external.dns)")
        }
        lines.append("MTU = \(mtu)")
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(local.serverPublicKey)")
        lines.append("Endpoint = 127.0.0.1:\(local.port)")
        lines.append("AllowedIPs = \(allowedIPs)")
        return lines.joined(separator: "\n")
    }
}
