import Foundation

// Кэш скачанного содержимого источников раздельного туннелирования. Списки
// блокировок — до ~1 МБ текста, в UserDefaults/Keychain им не место, поэтому
// текст лежит файлом, а метаданные (когда обновлялись, etag, число подсетей)
// — в UserDefaults, как и всё остальное лёгкое состояние приложения.
//
// Кэш общий на приложение и не относится к черновику профиля: отмена правок
// на экране профиля (✗) откатывает список ВЫБРАННЫХ источников, но не стирает
// уже скачанное — источник, отключённый и включённый обратно, не должен
// перекачиваться заново.
enum SplitTunnelListCache {
    struct Meta: Codable {
        var fetchedAt: Date
        var etag: String?
        var cidrCount: Int
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SplitTunnel", isDirectory: true)
    }

    private static func fileURL(for sourceID: UUID) -> URL {
        directory.appendingPathComponent("\(sourceID.uuidString).txt")
    }

    private static func allMeta(defaults: UserDefaults) -> [String: Meta] {
        guard let data = defaults.data(forKey: DefaultsKeys.splitTunnelMeta),
              let decoded = try? JSONDecoder().decode([String: Meta].self, from: data) else { return [:] }
        return decoded
    }

    private static func saveMeta(_ meta: [String: Meta], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        defaults.set(data, forKey: DefaultsKeys.splitTunnelMeta)
    }

    static func meta(for sourceID: UUID, defaults: UserDefaults = .standard) -> Meta? {
        allMeta(defaults: defaults)[sourceID.uuidString]
    }

    static func body(for sourceID: UUID) -> String? {
        try? String(contentsOf: fileURL(for: sourceID), encoding: .utf8)
    }

    // Атомарная запись: источник может обновляться в фоне, пока UI его читает.
    static func store(_ text: String, for sourceID: UUID, etag: String?, defaults: UserDefaults = .standard) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: fileURL(for: sourceID), atomically: true, encoding: .utf8)
        var all = allMeta(defaults: defaults)
        all[sourceID.uuidString] = Meta(fetchedAt: Date(), etag: etag, cidrCount: AllowedIPsBuilder.parseListLines(text).count)
        saveMeta(all, defaults: defaults)
    }

    static func remove(_ sourceID: UUID, defaults: UserDefaults = .standard) {
        try? FileManager.default.removeItem(at: fileURL(for: sourceID))
        var all = allMeta(defaults: defaults)
        all.removeValue(forKey: sourceID.uuidString)
        saveMeta(all, defaults: defaults)
    }
}
