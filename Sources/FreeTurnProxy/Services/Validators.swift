import Foundation

// Проверки форматов значений, общие для ручного ввода и разбора файла конфига.
enum Validators {
    // host:port — host = IPv4 либо доменное имя, port 1..65535.
    static func endpoint(_ s: String) -> Bool {
        guard let sep = s.lastIndex(of: ":") else { return false }
        let host = String(s[s.startIndex..<sep])
        let portStr = String(s[s.index(after: sep)...])
        guard !host.isEmpty, isHost(host) else { return false }
        guard let port = Int(portStr), (1...65535).contains(port) else { return false }
        return true
    }

    static func port(_ s: String) -> Bool {
        guard let p = Int(s) else { return false }
        return (1...65535).contains(p)
    }

    // Порт из "host:port" — нужен, чтобы поймать совпадение порта релея с
    // портом локального WG-responder'а: они оба на loopback, и второй просто
    // не забиндится («address already in use»).
    static func port(ofEndpoint s: String) -> Int? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard let sep = trimmed.lastIndex(of: ":") else { return nil }
        guard let p = Int(trimmed[trimmed.index(after: sep)...]), (1...65535).contains(p) else { return nil }
        return p
    }

    static func ipv4(_ s: String) -> Bool {
        let octets = s.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { o in
            guard o.count <= 3, let n = Int(o), String(n) == o else { return false }
            return (0...255).contains(n)
        }
    }

    static func isHost(_ s: String) -> Bool {
        if ipv4(s) { return true }
        let domain = "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$"
        return s.range(of: domain, options: .regularExpression) != nil
    }

    static func hexKey(_ s: String, length: Int = 64) -> Bool {
        guard s.count == length else { return false }
        return s.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil
    }

    static func vkLink(_ s: String) -> Bool {
        guard let url = URL(string: s),
              url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "vk.com" || host == "vk.ru"
            || host.hasSuffix(".vk.com") || host.hasSuffix(".vk.ru")
    }

    static func obfProfile(_ s: String) -> Bool {
        ["none", "rtpopus", "rtpopus2", "rtpopus3"].contains(s)
    }

    static func clientId(_ s: String) -> Bool {
        hexKey(s, length: 32)
    }

    // Список через запятую; пусто — используем дефолт ядра.
    static func dnsServers(_ s: String) -> Bool {
        let parts = s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.allSatisfy { ipv4($0) }
    }
}
