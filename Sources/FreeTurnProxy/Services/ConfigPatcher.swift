import Foundation

// Подменяет MTU, Endpoint и AllowedIPs в WireGuard/AWG конфиге, сохраняя
// все прочие ключи (включая AWG-параметры обфускации: Jc, Jmin, S1/S2,
// H1–H4 и т.д.). Если нужного ключа в секции нет — дописывает его, иначе
// split-tunnel и редирект на локальный прокси молча не применились бы.
enum ConfigPatcher {
    static func patch(_ config: String, allowedIPs: String, endpoint: String) -> String {
        enum Section { case none, interface, peer }
        var section: Section = .none
        var mtuDone = false, endpointDone = false, allowedDone = false
        var out: [String] = []

        func flushInterface() {
            if section == .interface, !mtuDone { out.append("MTU = 1280"); mtuDone = true }
        }
        func flushPeer() {
            if section == .peer {
                if !endpointDone { out.append("Endpoint = \(endpoint)"); endpointDone = true }
                if !allowedDone { out.append("AllowedIPs = \(allowedIPs)"); allowedDone = true }
            }
        }

        for line in config.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                flushInterface(); flushPeer()   // дописать недостающие ключи прошлой секции
                switch trimmed {
                case "[Interface]": section = .interface; mtuDone = false
                case "[Peer]":      section = .peer; endpointDone = false; allowedDone = false
                default:            section = .none
                }
                out.append(line); continue
            }

            let key = trimmed.components(separatedBy: "=").first?
                .trimmingCharacters(in: .whitespaces).lowercased() ?? ""

            switch (section, key) {
            case (.interface, "mtu"):   out.append("MTU = 1280"); mtuDone = true
            case (.peer, "endpoint"):   out.append("Endpoint = \(endpoint)"); endpointDone = true
            case (.peer, "allowedips"): out.append("AllowedIPs = \(allowedIPs)"); allowedDone = true
            default:                    out.append(line)
            }
        }
        flushInterface(); flushPeer()
        return out.joined(separator: "\n")
    }
}
