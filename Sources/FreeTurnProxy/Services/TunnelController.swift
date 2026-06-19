import Foundation

// Единая точка управления туннелем: собирает конфиг из выбранной конфигурации
// и сохранённой VK-ссылки, поднимает/гасит прокси и умеет дождаться состояния.
// Используется и из UI (TunnelViewModel), и из App Intents (шорткаты).
@MainActor
enum TunnelController {
    enum TunnelError: LocalizedError {
        case noSelectedConfig
        case noLink
        case timedOut
        case connectFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSelectedConfig: return "Не выбрана конфигурация"
            case .noLink:           return "Не задана ссылка на VK-звонок"
            case .timedOut:         return "Не удалось дождаться подключения"
            case .connectFailed(let m): return m
            }
        }
    }

    static var link: String {
        UserDefaults.standard.string(forKey: "manualLink")?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    // Поднимает туннель. Возврат сразу после успешного старта; готовность
    // ждём отдельно через waitUntilConnected.
    static func connect() throws {
        let proxy = ProxyManager.shared
        guard !proxy.isRunning else { return }
        guard let c = ConfigStore.shared.selected else { throw TunnelError.noSelectedConfig }
        let link = link
        guard !link.isEmpty else { throw TunnelError.noLink }

        var cfg = FreeTurnConfig(
            link: link,
            peer: c.peer,
            dns: c.dns.isEmpty ? nil : c.dns,
            listen: c.listen.isEmpty ? nil : c.listen
        )
        cfg.transport = c.transport
        cfg.obfKey = c.obfKey
        proxy.loadConfig(cfg, fileName: c.name)
        do {
            try proxy.start()
        } catch {
            proxy.deleteConfig()
            throw TunnelError.connectFailed(error.localizedDescription)
        }
    }

    static func disconnect() {
        ProxyManager.shared.stop()
    }

    // Ждём пока state не станет "connected"; на "error" — бросаем ошибку.
    static func waitUntilConnected(timeout: TimeInterval = 60) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let proxy = ProxyManager.shared
            if proxy.state == "connected" { return }
            if proxy.state == "error" {
                throw TunnelError.connectFailed(
                    proxy.errorMessage.isEmpty ? "Ошибка подключения" : proxy.errorMessage)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw TunnelError.timedOut
    }

    // Ждём пока туннель не погаснет (state пустой/idle, прокси не запущен).
    static func waitUntilDisconnected(timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let proxy = ProxyManager.shared
            if !proxy.isRunning || proxy.state.isEmpty || proxy.state == "idle" { return }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw TunnelError.timedOut
    }
}
