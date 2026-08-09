import Foundation

// clientId — обязательное поле CoreConfig в API ядра v2: mobile/api.go
// (startLocked) возвращает "clientId is required", если оно пустое. Ядро на
// мобиле не пишет файлов и само ничего не генерирует — заполнить обязаны мы.
//
// Это не механизм контроля доступа: доступ уже закрыт индивидуальными
// WireGuard-конфигами на клиента, без валидного конфига чужой упрётся
// максимум в форвард порта 51820 на самого себя. Поэтому здесь нет ни
// allowlist-обвязки, ни ротации — просто постоянное непустое значение.
//
// UserDefaults, не Keychain: Keychain недоступен на CI-раннере, и
// Keychain.wipeSecretsOnFreshInstall() затирал бы значение при каждой
// переустановке через SideStore.
enum ClientIdentity {
    static let current: String = {
        let defaults = UserDefaults.standard
        if let v = defaults.string(forKey: DefaultsKeys.coreClientId), !v.isEmpty {
            return v
        }
        let new = generate()
        defaults.set(new, forKey: DefaultsKeys.coreClientId)
        return new
    }()

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
