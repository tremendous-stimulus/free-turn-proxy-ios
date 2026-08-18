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
            case .noSelectedConfig: return "Не выбран профиль"
            case .noLink:           return "Не задана ссылка на VK-звонок"
            case .timedOut:         return "Не удалось дождаться подключения"
            case .connectFailed(let m): return m
            }
        }
    }

    static var links: [String] {
        ManualLinks.current
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Поднимает туннель. Возврат сразу после успешного старта; готовность
    // ждём отдельно через waitUntilConnected.
    static func connect() throws {
        let proxy = ProxyManager.shared
        guard !proxy.isRunning else { return }
        guard let c = ConfigStore.shared.selected else { throw TunnelError.noSelectedConfig }
        let links = links
        guard !links.isEmpty else { throw TunnelError.noLink }

        proxy.loadConfig(FreeTurnConfig(config: c, links: links), fileName: c.name)
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

    // Ждём пока state не станет .connected; на .error — бросаем ошибку.
    static func waitUntilConnected(timeout: TimeInterval = 60) async throws {
        var deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let proxy = ProxyManager.shared
            if proxy.state == .connected { return }
            if proxy.state == .error {
                throw TunnelError.connectFailed(
                    proxy.errorMessage.isEmpty ? "Ошибка подключения" : proxy.errorMessage)
            }
            // Пока пользователь решает captcha — не тратим бюджет ожидания, чтобы
            // интент продолжал работать до подключения или ошибки.
            if proxy.state == .captcha {
                deadline = Date().addingTimeInterval(timeout)
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw TunnelError.timedOut
    }

    // Ждём пока туннель не погаснет (state == .idle, прокси не запущен).
    static func waitUntilDisconnected(timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let proxy = ProxyManager.shared
            if !proxy.isRunning || proxy.state == .idle { return }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw TunnelError.timedOut
    }
}
