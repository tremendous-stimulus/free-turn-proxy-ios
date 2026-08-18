import Foundation

// Скачивает содержимое удалённых источников (preset/url) в
// SplitTunnelListCache. Никогда не зовётся с пути старта туннеля: фетч идёт
// через URLSession.shared мимо Go-protect и при поднимающемся AmneziaWG тонет
// в ещё не работающем туннеле — тот же эффект, что описан у
// BypassRoutes.swift:8-13 (там это стоило ~58 секунд задержки старта).
enum SplitTunnelListFetcher {
    // Пустой ответ не кэшируем — значит сервер недоступен, и затирать им
    // рабочий список означало бы терять уже настроенную маршрутизацию.
    @discardableResult
    static func refresh(_ source: SplitTunnelSource, defaults: UserDefaults = .standard) async -> Bool {
        guard source.kind.isRemote, let urlString = source.url, let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        if let etag = SplitTunnelListCache.meta(for: source.id, defaults: defaults)?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }

        if http.statusCode == 304 { return true } // кэш уже актуален
        guard http.statusCode == 200, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return false }

        let etag = http.value(forHTTPHeaderField: "ETag")
        try? SplitTunnelListCache.store(text, for: source.id, etag: etag, defaults: defaults)
        return true
    }

    // Обновляет источники старше `staleAfter`. Зовётся один раз после подъёма
    // туннеля, рядом с BypassRoutes.refresh() в ProxyManager — то есть уже при
    // живом туннеле, не на пути его старта.
    static func refreshStale(_ sources: [SplitTunnelSource], staleAfter: TimeInterval = 24 * 3600,
                              defaults: UserDefaults = .standard) async {
        for source in sources where source.kind.isRemote && source.isEnabled {
            let meta = SplitTunnelListCache.meta(for: source.id, defaults: defaults)
            let isStale = meta.map { Date().timeIntervalSince($0.fetchedAt) > staleAfter } ?? true
            guard isStale else { continue }
            await refresh(source, defaults: defaults)
        }
    }
}
