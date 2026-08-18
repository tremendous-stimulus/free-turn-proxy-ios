import Foundation

// Генерирует идентичность общей ЛОКАЛЬНОЙ половины (имя/порт + две пары
// ключей) — ничего не парсит, в отличие от ExternalWGConfigFactory, потому
// что локальная половина не зависит от конкретного внешнего сервера.
enum LocalWGConfigFactory {
    private static let nameSuffixChars = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static func randomName() -> String {
        "freeturn-" + String((0..<4).map { _ in nameSuffixChars.randomElement()! })
    }

    // existing — если конфиг уже был, переиспользуем его имя/порт, если не
    // задано явно (перегенерация ключей не должна сбрасывать настройки,
    // которые пользователь мог поправить руками).
    static func make(name: String? = nil, port: Int? = nil, existing: LocalWGConfig? = nil) -> LocalWGConfig {
        let server = LocalTunnelIdentity.generateKeyPair()
        let client = LocalTunnelIdentity.generateKeyPair()
        return LocalWGConfig(
            name: name ?? existing?.name ?? randomName(),
            port: port ?? existing?.port ?? LocalWGConfig.defaultPort,
            serverPrivateKey: server.privateKeyBase64,
            serverPublicKey: server.publicKeyBase64,
            clientPrivateKey: client.privateKeyBase64,
            clientPublicKey: client.publicKeyBase64,
            createdAt: Date()
        )
    }
}
