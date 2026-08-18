import Foundation

// Превращает SplitTunnelConfig пользователя в CIDR-списки, которые понимает
// Go-роутер (bypassCIDRs/bypassExcludeCIDRs — уже существующий механизм,
// см. BypassRoutes.swift). Разница только в источнике списка: BypassRoutes
// сама решает, что обходить (приватные сети + VK); здесь решает пользователь.
enum SplitTunnelResolver {
    // Список для bypassCIDRs. bypassExcludeCIDRs в эту функцию намеренно не
    // входит: исключение сети VPN-сервера считается всегда одинаково,
    // BypassRoutes.excludes(address:dns:), независимо от того, включено ли
    // раздельное туннелирование и в каком оно режиме — смешивать это с
    // подменяемым в тестах источником списка незачем.
    static func bypassCIDRs(for config: SplitTunnelConfig, defaults: UserDefaults = .standard) -> [String] {
        guard config.enabled else {
            return BypassRoutes.current(defaults: defaults)
        }

        let userRanges = userRanges(for: config)

        switch config.mode {
        case .exclude:
            let userCIDRs = userRanges.flatMap { r in
                var out: [String] = []
                AllowedIPsBuilder.appendPrefixes(start: r.start, end: r.end, into: &out)
                return out
            }
            return BypassRoutes.current(defaults: defaults) + userCIDRs

        case .include:
            // Пустой список включений в комплементе даёт 0.0.0.0/0 — весь
            // трафик ушёл бы мимо VPN. Отказываемся применять и логируем ERR;
            // UI обязан не давать сохранить такую конфигурацию (canConfirm),
            // но защититься нужно и на этом уровне — на случай старых
            // сохранённых профилей или гонки состояния.
            guard !userRanges.isEmpty else {
                DispatchQueue.main.async {
                    ErrorLogger.shared.appendAppLine(level: "ERR",
                        message: "Раздельное туннелирование (включения) отключено: список источников пуст")
                }
                return BypassRoutes.current(defaults: defaults)
            }
            let complement = AllowedIPsBuilder.complement(of: userRanges)
            // IPv6 в режиме включений комплемент не строит (только IPv4) —
            // безопасное поведение: IPv6-трафик остаётся в туннеле.
            return complement + BypassRoutes.current(defaults: defaults)
        }
    }

    private static func userRanges(for config: SplitTunnelConfig) -> [AllowedIPsBuilder.IPRange] {
        let texts = config.activeSources.compactMap { source -> String? in
            switch source.kind {
            case .manual, .file: return source.body
            case .preset, .url: return SplitTunnelListCache.body(for: source.id)
            }
        }
        return AllowedIPsBuilder.merge(texts.flatMap(AllowedIPsBuilder.parseListLines))
    }
}
