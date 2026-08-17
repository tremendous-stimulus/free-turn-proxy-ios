import Foundation

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
    static func excludes(address: String) -> [String] {
        address
            .split(separator: ",")
            .compactMap { network(of: $0.trimmingCharacters(in: .whitespaces)) }
    }

    // "10.8.0.2/24" → "10.8.0.0/24". Голый адрес трактуем как /32.
    static func network(of cidr: String) -> String? {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        guard let addr = parts.first.map(String.init), let value = ipv4(addr) else { return nil }
        let bits = parts.count == 2 ? Int(parts[1]) ?? 32 : 32
        guard (0...32).contains(bits) else { return nil }
        let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << (32 - bits)
        return "\(string(from: value & mask))/\(bits)"
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
