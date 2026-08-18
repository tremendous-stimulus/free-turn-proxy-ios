import Foundation
import Network

// Что роутер ftun уводит мимо туннеля (план vpn-lexical-rossum.md, фаза 5.2).
// Список считается здесь, а применяется в Go: Swift знает и подсети VK, и
// адрес самого туннеля, а роутеру нужны только готовые CIDR.
//
// Критично: current() синхронный и в сеть не ходит. Фетч подсетей у RIPE идёт
// через URLSession, то есть мимо protect (тот покрывает только сокеты
// Go-ядра), и при поднятом AmneziaWG тонет в ещё не работающем туннеле —
// локальная половина вставала на ~58 секунд позже внешней, пока запрос не
// отваливался по таймауту. Поэтому сеть тут только в refresh(), который
// готовит список к СЛЕДУЮЩЕМУ запуску и зовётся уже при живом туннеле.
enum BypassRoutes {
    // Приватные и служебные диапазоны: без них при поднятом туннеле пропадает
    // локальная сеть, а link-local и CGNAT гонять через VPS бессмысленно.
    static let privateCIDRs = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "100.64.0.0/10",
    ]

    static func current(defaults: UserDefaults = .standard) -> [String] {
        let vk = defaults.stringArray(forKey: DefaultsKeys.bypassVKCIDRs) ?? AllowedIPsBuilder.vkFallbackCIDRs
        return privateCIDRs + vk
    }

    // Пустой ответ не кэшируем: он означает недоступность RIPE, и затирать им
    // рабочий список — значит терять маршрутизацию VK до следующего успеха.
    static func refresh(defaults: UserDefaults = .standard) async {
        let fetched = await AllowedIPsBuilder.fetchVKCIDRs()
        guard !fetched.isEmpty else { return }
        defaults.set(fetched, forKey: DefaultsKeys.bypassVKCIDRs)
    }

    // Сеть самого VPN-сервера обязана остаться в туннеле: у типового конфига
    // это 10.8.0.0/24, и без исключения она попала бы под «приватное — мимо
    // туннеля», то есть трафик к собственному серверу ушёл бы напрямую.
    //
    // Address почти всегда host-префикс (10.8.0.2/32), и тогда сеть из него не
    // выводится — исключение схлопнулось бы в один собственный адрес, а
    // DNS-резолвер туннеля (10.8.0.1) ушёл бы мимо. Поэтому адреса DNS входят
    // в исключение отдельно, как /32.
    static func excludes(address: String, dns: String = "") -> [String] {
        let fromAddress = hosts(in: address).compactMap { network(of: $0) }
        let fromDNS = hosts(in: dns).compactMap { network(of: hostPrefix($0)) }
        var seen = Set<String>()
        return (fromAddress + fromDNS).filter { seen.insert($0).inserted }
    }

    private static func hosts(in list: String) -> [String] {
        list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // DNS в конфиге — голые адреса; на всякий случай режем чужой префикс,
    // исключать по нему целую подсеть мы не хотим.
    private static func hostPrefix(_ s: String) -> String {
        String(s.split(separator: "/", maxSplits: 1).first ?? "")
    }

    // "10.8.0.2/24" → "10.8.0.0/24", "fd00::2/64" → "fd00::/64". Голый адрес
    // трактуем как хост (/32 и /128 соответственно).
    static func network(of cidr: String) -> String? {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        guard let addr = parts.first.map(String.init), !addr.isEmpty else { return nil }
        if addr.contains(":") {
            let bits = parts.count == 2 ? Int(parts[1]) ?? 128 : 128
            return ipv6Network(addr, bits: bits)
        }
        guard let value = ipv4(addr) else { return nil }
        let bits = parts.count == 2 ? Int(parts[1]) ?? 32 : 32
        guard (0...32).contains(bits) else { return nil }
        let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << (32 - bits)
        return "\(string(from: value & mask))/\(bits)"
    }

    // IPv6 в bypass-списках пока не встречается, но исключение обязано
    // отработать и на IPv6-конфиге: молча выкинуть адрес сервера значило бы
    // увести его трафик мимо туннеля в тот день, когда IPv6-диапазоны там
    // появятся.
    private static func ipv6Network(_ addr: String, bits: Int) -> String? {
        guard (0...128).contains(bits), let ip = IPv6Address(addr) else { return nil }
        var bytes = [UInt8](ip.rawValue)
        for i in bytes.indices {
            let keep = max(0, min(8, bits - i * 8))
            bytes[i] &= keep == 0 ? 0 : ~UInt8(0) << (8 - keep)
        }
        guard let masked = IPv6Address(Data(bytes)) else { return nil }
        return "\(masked.debugDescription)/\(bits)"
    }

    private static func ipv4(_ s: String) -> UInt32? {
        let octets = s.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard let n = UInt32(octet), n <= 255 else { return nil }
            value = value << 8 | n
        }
        return value
    }

    private static func string(from value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
