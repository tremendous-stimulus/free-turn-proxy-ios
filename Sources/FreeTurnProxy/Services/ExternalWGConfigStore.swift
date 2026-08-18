import Foundation

// Хранилище ExternalWGConfig — только Keychain, как и LocalWGConfigStore.
// В отличие от него ключ — id профиля: у разных профилей разные внешние
// серверы. Инжектируемое — тесты подставляют свою реализацию (Keychain
// недоступен на CI-раннере, см. CLAUDE.md).
protocol ExternalWGConfigStoring {
    func save(_ config: ExternalWGConfig, for profileID: UUID)
    func load(for profileID: UUID) -> ExternalWGConfig?
    func delete(for profileID: UUID)
}

struct KeychainExternalWGConfigStore: ExternalWGConfigStoring {
    private static func account(for profileID: UUID) -> String {
        "externalWGConfig.v1.\(profileID.uuidString)"
    }

    func save(_ config: ExternalWGConfig, for profileID: UUID) {
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else { return }
        Keychain.set(json, for: Self.account(for: profileID))
    }

    func load(for profileID: UUID) -> ExternalWGConfig? {
        guard let json = Keychain.get(Self.account(for: profileID)),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExternalWGConfig.self, from: data)
    }

    func delete(for profileID: UUID) {
        Keychain.remove(Self.account(for: profileID))
    }
}
