import AppIntents

// Подключение к туннелю. Ждёт, пока state не станет "connected".
@available(iOS 16.0, *)
struct ConnectTunnelIntent: AppIntent {
    static var title: LocalizedStringResource = "Подключиться к туннелю"
    static var description = IntentDescription("Поднимает прокси для выбранной конфигурации и ждёт подключения.")
    // Пытаемся работать в фоне; если iOS не даст — выполнится при открытом приложении.
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await TunnelController.connect()
        try await TunnelController.waitUntilConnected()
        return .result()
    }
}

// Отключение туннеля. Ждёт, пока state не опустеет.
@available(iOS 16.0, *)
struct DisconnectTunnelIntent: AppIntent {
    static var title: LocalizedStringResource = "Отключиться от туннеля"
    static var description = IntentDescription("Гасит прокси и ждёт полного отключения.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await TunnelController.disconnect()
        try await TunnelController.waitUntilDisconnected()
        return .result()
    }
}

@available(iOS 16.0, *)
struct TunnelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectTunnelIntent(),
            phrases: [
                "Подключить туннель в \(.applicationName)",
                "Включить \(.applicationName)",
            ],
            shortTitle: "Подключиться",
            systemImageName: "bolt.horizontal.circle"
        )
        AppShortcut(
            intent: DisconnectTunnelIntent(),
            phrases: [
                "Отключить туннель в \(.applicationName)",
                "Выключить \(.applicationName)",
            ],
            shortTitle: "Отключиться",
            systemImageName: "bolt.slash"
        )
    }
}
