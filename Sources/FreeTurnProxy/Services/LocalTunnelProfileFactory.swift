import Foundation

// Собирает LocalTunnelProfile из введённого пользователем .conf: парсит
// Address/DNS секции [Interface] (см. LocalConfigBuilder — роутер Фазы 1
// чистый L3 pass-through без NAT, поэтому Address обязан совпадать с
// реальным конфигом) и генерирует две пары ключей.
enum LocalTunnelProfileFactory {
    enum FactoryError: LocalizedError {
        case missingAddress
        var errorDescription: String? { "В конфиге не найден Address — обязателен для локального туннеля" }
    }

    static func make(id: UUID = UUID(), remoteConfText: String) throws -> LocalTunnelProfile {
        guard let address = interfaceField("Address", in: remoteConfText) else {
            throw FactoryError.missingAddress
        }
        let dns = interfaceField("DNS", in: remoteConfText) ?? ""
        let server = LocalTunnelIdentity.generateKeyPair()
        let client = LocalTunnelIdentity.generateKeyPair()
        return LocalTunnelProfile(
            id: id,
            remoteConfText: remoteConfText,
            serverPrivateKey: server.privateKeyBase64,
            serverPublicKey: server.publicKeyBase64,
            clientPrivateKey: client.privateKeyBase64,
            clientPublicKey: client.publicKeyBase64,
            address: address,
            dns: dns,
            remoteEndpoint: sectionField("Endpoint", section: "[Peer]", in: remoteConfText) ?? "",
            createdAt: Date(),
            sentAt: nil
        )
    }

    private static func interfaceField(_ key: String, in config: String) -> String? {
        sectionField(key, section: "[Interface]", in: config)
    }

    // Построчный поиск "Ключ = значение" в заданной секции — та же схема,
    // что и в ConfigPatcher, без полноценного парсера.
    private static func sectionField(_ key: String, section: String, in config: String) -> String? {
        var inSection = false
        for line in config.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inSection = (trimmed == section)
                continue
            }
            guard inSection else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            guard k.lowercased() == key.lowercased() else { continue }
            let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
