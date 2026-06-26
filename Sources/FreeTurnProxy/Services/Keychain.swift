import Foundation
import Security

// Тонкая обёртка над Keychain для строковых секретов (VK access-token и т.п.).
// kSecClassGenericPassword, доступ — только после первой разблокировки на этом
// устройстве, без синхронизации в iCloud.
enum Keychain {
    private static let service = "com.freeturn.proxy"

    // Аккаунты секретов.
    static let vkTokenAccount = "vkAccessToken"

    // Keychain переживает удаление приложения, а UserDefaults — нет, и хука на
    // удаление iOS не даёт. Поэтому при первом запуске после свежей установки
    // (флага ещё нет — его стёрло вместе с приложением) вычищаем секреты,
    // оставшиеся от предыдущей установки.
    static func wipeSecretsOnFreshInstall() {
        let d = UserDefaults.standard
        let flag = DefaultsKeys.keychainBoundToInstall
        guard !d.bool(forKey: flag) else { return }
        remove(vkTokenAccount)
        d.set(true, forKey: flag)
    }

    static func set(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else { remove(account); return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
