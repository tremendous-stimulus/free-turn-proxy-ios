import Foundation

// Хранилище сохранённых конфигураций + текущий выбор. Персистится в
// UserDefaults как JSON. Импорт/экспорт идёт через файлы .freeturn.
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published private(set) var configs: [SavedConfig] = []
    @Published private(set) var selectedID: UUID?

    // Стек удалений — каждое потряхивание отменяет последнее удаление.
    struct Deleted: Equatable { var config: SavedConfig; var index: Int }
    @Published private(set) var deletedStack: [Deleted] = []

    // Разовая подсказка про шейк-отмену (показываем после первого удаления).
    @Published private(set) var showShakeHint = false

    // Импорт открытого .freeturn — редактор на вкладке «Туннель» подхватит.
    @Published var pendingImport: SavedConfig?

    private let d = UserDefaults.standard
    private let configsKey = "savedConfigs.v1"
    private let selectedKey = "savedConfigs.selected"
    private let shakeHintKey = "shakeHintPending"

    private init() { load() }

    var lastDeleted: Deleted? { deletedStack.last }

    var selected: SavedConfig? { configs.first { $0.id == selectedID } }

    // MARK: – Мутации

    func add(_ c: SavedConfig) {
        configs.append(c)
        selectedID = c.id
        persist()
    }

    func update(_ c: SavedConfig) {
        guard let i = configs.firstIndex(where: { $0.id == c.id }) else { return }
        configs[i] = c
        persist()
    }

    func delete(_ c: SavedConfig) {
        guard let i = configs.firstIndex(where: { $0.id == c.id }) else { return }
        deletedStack.append(Deleted(config: configs[i], index: i))
        configs.remove(at: i)
        if selectedID == c.id { selectedID = configs.first?.id }
        persist()
        maybeShowShakeHint()
    }

    func undoDelete() {
        guard let last = deletedStack.popLast() else { return }
        let idx = min(last.index, configs.count)
        configs.insert(last.config, at: idx)
        selectedID = last.config.id
        persist()
    }

    // Показываем подсказку про шейк ровно один раз за всё время — после
    // самого первого удаления. Флаг персистится между запусками.
    private func maybeShowShakeHint() {
        let pending = (d.object(forKey: shakeHintKey) as? Bool) ?? true
        guard pending else { return }
        d.set(false, forKey: shakeHintKey)
        showShakeHint = true
    }

    func dismissShakeHint() { showShakeHint = false }

    func select(_ id: UUID) {
        selectedID = id
        persistSelected()
    }

    // MARK: – Импорт / экспорт (.freeturn)

    // Открыли .freeturn через приложение — парсим тем же методом и отдаём
    // редактору (через pendingImport). Если файл не наш (например, открыли
    // приложение через SideStore) — молча игнорируем, без алерта.
    func receiveFile(_ url: URL) {
        if let cfg = try? ConfigCodec.parse(contentsOf: url) {
            pendingImport = cfg
        }
    }

    func exportFile(_ c: SavedConfig) -> URL? {
        guard let data = try? ConfigCodec.encode(c) else { return nil }
        let safe = c.name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined()
        let fileName = (safe.isEmpty ? "config" : safe) + ".freeturn"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    // MARK: – Персист

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) { d.set(data, forKey: configsKey) }
        persistSelected()
    }

    private func persistSelected() {
        d.set(selectedID?.uuidString, forKey: selectedKey)
    }

    private func load() {
        if let data = d.data(forKey: configsKey),
           let list = try? JSONDecoder().decode([SavedConfig].self, from: data) {
            configs = list
        } else {
            migrateLegacy()
        }
        if let s = d.string(forKey: selectedKey), let id = UUID(uuidString: s),
           configs.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = configs.first?.id
        }
    }

    // Однократный перенос старой одиночной ручной конфигурации в список.
    private func migrateLegacy() {
        let peer = d.string(forKey: "manualPeer")?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !peer.isEmpty else { return }
        configs = [SavedConfig(
            name: "Моя конфигурация",
            peer: peer,
            obfKey: d.string(forKey: "manualObfKey") ?? "",
            dns: d.string(forKey: "manualDns") ?? "",
            listen: d.string(forKey: "manualListen") ?? "",
            transport: d.string(forKey: "manualTransport") ?? "udp"
        )]
        persist()
    }
}
