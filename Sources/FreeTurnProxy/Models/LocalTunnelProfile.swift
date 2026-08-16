import Foundation

// Реальный wg/awg-конфиг пользователя плюс собственные ключи локального
// туннеля (план vpn-lexical-rossum.md, фаза 2). Хранится только в Keychain
// через LocalTunnelProfileStore, не в UserDefaults, где живёт ConfigStore —
// SavedConfig держит лишь ссылку (wgProfileID) и флаг режима.
struct LocalTunnelProfile: Codable, Equatable {
    var id: UUID
    var remoteConfText: String
    // Ключ локального WG-responder'а (127.0.0.1:9000, куда стучится AmneziaWG).
    var serverPrivateKey: String
    var serverPublicKey: String
    // Ключ, который уходит в AmneziaWG как клиентская идентичность.
    var clientPrivateKey: String
    var clientPublicKey: String
    // Address/DNS из реального конфига — роутер (golib/ftun) чистый L3
    // pass-through без NAT, поэтому исходящий IP обязан совпадать.
    var address: String
    var dns: String
}
