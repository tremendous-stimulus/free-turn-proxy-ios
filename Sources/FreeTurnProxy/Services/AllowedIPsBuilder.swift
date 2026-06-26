import Foundation

// Считает AllowedIPs для inverse split-tunnel: ВЕСЬ интернет (0.0.0.0/0)
// за вычетом выбранного набора исключений и локальных сетей.
enum AllowedIPsBuilder {

    // MARK: – Scheme

    enum Scheme: String, CaseIterable, Identifiable {
        case fullInternet   = "Весь интернет"
        case withoutWhitelist = "Всё кроме белых списков"
        case withoutVK      = "Всё кроме подсетей VK"
        var id: String { rawValue }

        var hint: String {
            switch self {
            case .fullInternet:    return "Весь трафик идёт через VPN"
            case .withoutWhitelist: return "Белый список РФ (VK, банки и т.д.) — напрямую"
            case .withoutVK:       return "Только подсети VK идут напрямую"
            }
        }
    }

    // MARK: – Sources

    // Белый список CIDR РФ (веерные отключения).
    private static let whitelistURL = URL(string:
        "https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt"
    )!

    // RIPE stat API: анонсируемые префиксы основного ASN ВКонтакте (AS47764).
    private static let vkRipeURL = URL(string:
        "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS47764"
    )!

    // Запасной список VK-префиксов на случай недоступности RIPE API.
    private static let vkFallbackCIDRs = [
        "87.240.128.0/18", "185.68.16.0/22", "93.186.224.0/21",
        "5.61.16.0/20", "212.119.96.0/20",
    ]

    // Локальные/служебные диапазоны — всегда мимо туннеля. 127/8 критичен:
    // там слушает локальный прокси (127.0.0.1:9000), иначе WG-хендшейк
    // к нему зациклится внутрь туннеля.
    private static let localRanges = [
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
        "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/3",
    ]

    // MARK: – Errors

    enum BuildError: LocalizedError {
        case fetch
        case empty
        var errorDescription: String? {
            switch self {
            case .fetch: return "Не удалось загрузить список адресов — проверьте интернет"
            case .empty: return "Список адресов пуст или недоступен"
            }
        }
    }

    // MARK: – Public entry point

    static func build(scheme: Scheme) async throws -> String {
        switch scheme {
        case .fullInternet:
            return "0.0.0.0/0"
        case .withoutWhitelist:
            return try await buildWithoutWhitelist()
        case .withoutVK:
            return try await buildWithoutVK()
        }
    }

    // MARK: – Private builders

    private static func buildWithoutWhitelist() async throws -> String {
        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(from: whitelistURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw BuildError.fetch }
            data = d
        } catch {
            throw BuildError.fetch
        }
        guard let text = String(data: data, encoding: .utf8) else { throw BuildError.fetch }
        let whitelist = parseCIDRs(text)
        guard !whitelist.isEmpty else { throw BuildError.empty }
        return try buildExcluding(whitelist)
    }

    private static func buildWithoutVK() async throws -> String {
        let vkCIDRStrings = await fetchVKCIDRs()
        let vkRanges = vkCIDRStrings.compactMap(parseCIDR)
        guard !vkRanges.isEmpty else { throw BuildError.empty }
        return try buildExcluding(vkRanges)
    }

    private static func buildExcluding(_ excludes: [IPRange]) throws -> String {
        var all = excludes
        all.append(contentsOf: localRanges.compactMap(parseCIDR))
        let prefixes = complement(of: all)
        guard !prefixes.isEmpty else { throw BuildError.empty }
        return prefixes.joined(separator: ", ")
    }

    // Тянем префиксы AS47764 из RIPE stat; при ошибке — fallback-константы.
    private static func fetchVKCIDRs() async -> [String] {
        struct RIPEPrefix: Decodable { let prefix: String }
        struct RIPEData: Decodable { let prefixes: [RIPEPrefix] }
        struct RIPEResponse: Decodable { let data: RIPEData }

        if let (d, resp) = try? await URLSession.shared.data(from: vkRipeURL),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let parsed = try? JSONDecoder().decode(RIPEResponse.self, from: d),
           !parsed.data.prefixes.isEmpty {
            return parsed.data.prefixes.map(\.prefix)
        }
        return vkFallbackCIDRs
    }

    // MARK: - Parsing

    struct IPRange: Equatable { var start: UInt32; var end: UInt32 }

    private static let cidrRegex = try! NSRegularExpression(
        pattern: #"(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})"#
    )

    static func parseCIDRs(_ s: String) -> [IPRange] {
        let ns = s as NSString
        let matches = cidrRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out: [IPRange] = []
        out.reserveCapacity(matches.count)
        for m in matches {
            func octet(_ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? -1 }
            let o0 = octet(1), o1 = octet(2), o2 = octet(3), o3 = octet(4), pfx = octet(5)
            guard (0...255).contains(o0), (0...255).contains(o1),
                  (0...255).contains(o2), (0...255).contains(o3),
                  (0...32).contains(pfx) else { continue }
            let ip = UInt32(o0) << 24 | UInt32(o1) << 16 | UInt32(o2) << 8 | UInt32(o3)
            out.append(range(ip: ip, prefix: pfx))
        }
        return out
    }

    static func parseCIDR(_ cidr: String) -> IPRange? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let pfx = Int(parts[1]) else { return nil }
        let octs = parts[0].split(separator: ".").compactMap { Int($0) }
        guard octs.count == 4 else { return nil }
        let ip = UInt32(octs[0]) << 24 | UInt32(octs[1]) << 16 | UInt32(octs[2]) << 8 | UInt32(octs[3])
        return range(ip: ip, prefix: pfx)
    }

    static func range(ip: UInt32, prefix: Int) -> IPRange {
        if prefix <= 0 { return IPRange(start: 0, end: 0xFFFF_FFFF) }
        if prefix >= 32 { return IPRange(start: ip, end: ip) }
        let size = UInt64(1) << (32 - prefix)
        let base = UInt64(ip) & ~(size - 1)
        return IPRange(start: UInt32(base), end: UInt32(base + size - 1))
    }

    // MARK: - Complement (0.0.0.0/0 минус excludes)

    static func complement(of ranges: [IPRange]) -> [String] {
        let merged = merge(ranges)
        var gaps: [IPRange] = []
        var cur: UInt64 = 0
        for r in merged {
            if UInt64(r.start) > cur {
                gaps.append(IPRange(start: UInt32(cur), end: r.start - 1))
            }
            cur = max(cur, UInt64(r.end) + 1)
        }
        if cur <= 0xFFFF_FFFF {
            gaps.append(IPRange(start: UInt32(cur), end: 0xFFFF_FFFF))
        }

        var out: [String] = []
        for g in gaps { appendPrefixes(start: g.start, end: g.end, into: &out) }
        return out
    }

    static func merge(_ ranges: [IPRange]) -> [IPRange] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { $0.start < $1.start }
        var out: [IPRange] = [sorted[0]]
        for r in sorted.dropFirst() {
            if UInt64(r.start) <= UInt64(out[out.count - 1].end) + 1 {
                if r.end > out[out.count - 1].end { out[out.count - 1].end = r.end }
            } else {
                out.append(r)
            }
        }
        return out
    }

    // Разбивает диапазон [start, end] на минимальный набор CIDR-префиксов.
    static func appendPrefixes(start: UInt32, end: UInt32, into out: inout [String]) {
        var s = UInt64(start)
        let e = UInt64(end)
        while s <= e {
            let sv = UInt32(s)
            let alignBits = sv == 0 ? 32 : sv.trailingZeroBitCount
            var size = UInt64(1) << alignBits
            let remaining = e - s + 1
            while size > remaining { size >>= 1 }
            let prefixLen = 32 - size.trailingZeroBitCount
            out.append(cidr(UInt32(s), prefixLen))
            s += size
        }
    }

    static func cidr(_ ip: UInt32, _ prefix: Int) -> String {
        "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)/\(prefix)"
    }
}
