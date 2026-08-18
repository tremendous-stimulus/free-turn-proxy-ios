import Foundation

// Собирает ExternalWGConfig из введённого пользователем .conf: парсит
// Address/DNS/Endpoint. Локальная половина (LocalWGConfigFactory) сюда не
// входит — она не зависит от конкретного внешнего сервера.
enum ExternalWGConfigFactory {
    enum FactoryError: LocalizedError {
        case missingAddress
        var errorDescription: String? { "В конфиге не найден Address — обязателен для локального туннеля" }
    }

    static func make(remoteConfText: String) throws -> ExternalWGConfig {
        guard let address = interfaceField("Address", in: remoteConfText) else {
            throw FactoryError.missingAddress
        }
        let dns = interfaceField("DNS", in: remoteConfText) ?? ""
        return ExternalWGConfig(
            remoteConfText: remoteConfText,
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
