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
}
