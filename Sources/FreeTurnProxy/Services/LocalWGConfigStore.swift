import Foundation

// Хранилище LocalWGConfig — только Keychain: реальный конфиг и ключи не
// должны оседать в UserDefaults. Один фиксированный аккаунт, а не по UUID:
// конфиг общий на всё приложение (см. LocalWGConfig). Инжектируемое, потому
// что Keychain недоступен на CI-раннере (см. CLAUDE.md) — тесты подставляют
// свою реализацию, как ConfigStore(defaults:).
protocol LocalWGConfigStoring {
    func save(_ config: LocalWGConfig)
    func load() -> LocalWGConfig?
    func delete()
}

struct KeychainLocalWGConfigStore: LocalWGConfigStoring {
    private static let account = "localWGConfig.v1"

    func save(_ config: LocalWGConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        Keychain.set(json, for: Self.account)
    }

    func load() -> LocalWGConfig? {
        guard let json = Keychain.get(Self.account),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocalWGConfig.self, from: data)
    }

    func delete() {
        Keychain.remove(Self.account)
    }
}
