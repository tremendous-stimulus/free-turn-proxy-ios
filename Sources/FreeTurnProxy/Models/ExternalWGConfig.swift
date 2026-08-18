import Foundation

// Конфиг ВНЕШНЕГО VPN-сервера пользователя — привязан к конкретному профилю
// (SavedConfig), потому что у разных профилей могут быть разные серверы.
// Живёт в Keychain через ExternalWGConfigStoring, ключ — id профиля.
// Локальная половина (порт, ключи responder'а) общая на всё приложение,
// см. LocalWGConfig.
struct ExternalWGConfig: Codable, Equatable {
    var remoteConfText: String
    // Address/DNS из реального конфига — роутер (golib/ftun) чистый L3
    // pass-through без NAT, поэтому исходящий IP обязан совпадать.
    var address: String
    var dns: String
    // Endpoint из [Peer] реального конфига — только для отображения в
    // карточке «Конфиг вашего VPN-сервера», в маршрутизации не участвует.
    var remoteEndpoint: String
    var createdAt: Date
    // nil, пока пользователь ни разу не отправлял конфиг в AmneziaWG.
    var sentAt: Date?
}
