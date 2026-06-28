import Foundation
import UniformTypeIdentifiers

extension UTType {
    // Должен совпадать с UTExportedTypeDeclarations в Info.plist.
    static let freeturn = UTType(exportedAs: "com.freeturn.proxy.config")
}

enum ConfigCodecError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Файл не похож на конфигурацию Free Turn — не удалось прочитать ни одного поля"
        }
    }
}

// Единый формат файла .freeturn — JSON. Один и тот же parse используется и при
// открытии файла через приложение, и при импорте в редакторе. id не сохраняем:
// он нужен только в рантайме для списка/выбора и присваивается заново при импорте.
//
// Парсинг «мягкий»: лишние ключи игнорируются, значения не валидируются здесь —
// это делает редактор, подсвечивая ошибки. Бросаем только если не удалось
// вытащить вообще ни одного поля (файл сломан).
enum ConfigCodec {
    private struct DTO: Codable {
        var name: String?
        var peer: String?
        var obfKey: String?
        var dns: String?
        var listen: String?
        var transport: String?
    }

    static func encode(_ c: SavedConfig) throws -> Data {
        let dto = DTO(name: c.name, peer: c.peer, obfKey: c.obfKey,
                      dns: c.dns, listen: c.listen, transport: c.transport)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(dto)
    }

    static func parse(_ data: Data) throws -> SavedConfig {
        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw ConfigCodecError.unreadable
        }
        func t(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespaces) }
        let transport = t(dto.transport).lowercased()
        let cfg = SavedConfig(
            name: t(dto.name),
            peer: t(dto.peer),
            obfKey: t(dto.obfKey),
            dns: t(dto.dns),
            listen: t(dto.listen),
            transport: (transport == "udp" || transport == "tcp") ? transport : "udp"
        )
        let loadedSomething = ![cfg.name, cfg.peer, cfg.obfKey, cfg.dns, cfg.listen].allSatisfy(\.isEmpty)
        guard loadedSomething else { throw ConfigCodecError.unreadable }
        return cfg
    }

    static func parse(contentsOf url: URL) throws -> SavedConfig {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ConfigCodecError.unreadable }
        return try parse(data)
    }
}
