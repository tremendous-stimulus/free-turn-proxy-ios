import Foundation

// Локальный адрес прокси выбранной конфигурации: на него биндится TURN-клиент
// и на него же патчится Endpoint в конфиге AmneziaWG (вкладка VPN).
enum AppSettings {
    static let defaultListen = "127.0.0.1:9000"

    @MainActor static var listen: String {
        let v = ConfigStore.shared.selected?.listen.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? defaultListen : v
    }
}
