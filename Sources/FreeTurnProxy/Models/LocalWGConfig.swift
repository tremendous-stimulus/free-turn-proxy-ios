import Foundation

// Общая ЛОКАЛЬНАЯ половина WG-in-WG (план vpn-lexical-rossum.md, фаза 2/5.3) —
// один responder на всё приложение, один порт, одна пара ключей. Не зависит
// от того, какой профиль сейчас активен — в отличие от ExternalWGConfig
// (конфиг ВНЕШНЕГО VPN-сервера), который привязан к конкретному профилю:
// у разных профилей разные серверы, но локальный туннель на устройстве один.
struct LocalWGConfig: Codable, Equatable {
    static let defaultPort = 9001

    var name: String
    // Порт локального WG-responder'а (127.0.0.1:port, куда стучится
    // AmneziaWG). Порт туннеля (апстрим-релей) — отдельное, уже редактируемое
    // поле SavedConfig.listen, дефолт 127.0.0.1:9000.
    var port: Int
    var serverPrivateKey: String
    var serverPublicKey: String
    // Ключ, который уходит в AmneziaWG как клиентская идентичность.
    var clientPrivateKey: String
    var clientPublicKey: String
    var createdAt: Date
}
