import Foundation

// Хранилище LocalTunnelProfile — только Keychain: реальный конфиг и ключи
// не должны оседать в UserDefaults. Инжектируемое, потому что Keychain
// недоступен на CI-раннере (см. CLAUDE.md) — тесты подставляют свою
// реализацию, как ConfigStore(defaults:).
protocol LocalTunnelProfileStoring {
    func save(_ profile: LocalTunnelProfile)
    func load(_ id: UUID) -> LocalTunnelProfile?
    func delete(_ id: UUID)
}

struct KeychainLocalTunnelProfileStore: LocalTunnelProfileStoring {
    private func account(for id: UUID) -> String { "wgProfile.\(id.uuidString)" }

    func save(_ profile: LocalTunnelProfile) {
        guard let data = try? JSONEncoder().encode(profile),
              let json = String(data: data, encoding: .utf8) else { return }
        Keychain.set(json, for: account(for: profile.id))
    }

    func load(_ id: UUID) -> LocalTunnelProfile? {
        guard let json = Keychain.get(account(for: id)),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocalTunnelProfile.self, from: data)
    }

    func delete(_ id: UUID) {
        Keychain.remove(account(for: id))
    }
}
