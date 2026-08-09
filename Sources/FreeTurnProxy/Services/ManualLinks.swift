import Foundation

// Список VK-ссылок для подключения. Раньше была одна ссылка (manualLink) —
// теперь можно задать несколько: ядро v2.1.1 принимает vk.links[], каждая
// дополнительная ссылка даёт свой пул из turn.n потоков. Общий для всех
// сохранённых конфигураций, как и раньше был manualLink.
enum ManualLinks {
    static var current: [String] {
        get {
            let d = UserDefaults.standard
            if let data = d.data(forKey: DefaultsKeys.manualLinks),
               let list = try? JSONDecoder().decode([String].self, from: data) {
                return list
            }
            // Однократная миграция старого ключа с одной ссылкой.
            let legacy = d.string(forKey: DefaultsKeys.manualLink)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let migrated = legacy.isEmpty ? [] : [legacy]
            persist(migrated)
            return migrated
        }
        set { persist(newValue) }
    }

    private static func persist(_ links: [String]) {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(links) {
            d.set(data, forKey: DefaultsKeys.manualLinks)
        }
    }
}
