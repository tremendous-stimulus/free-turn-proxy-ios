import Foundation

// Раздельное туннелирование для режима «Туннель + WireGuard». Список подсетей
// собирается здесь, а применяет его Go-роутер (ftun): совпало с bypass-набором
// — пакет уходит в netstack мимо VPN, иначе — в туннель.
//
// Источник хранит ОПИСАНИЕ, а не скачанное содержимое: списки блокировок
// доходят до мегабайта текста, и в UserDefaults (куда персистится SavedConfig)
// им не место — они лежат в SplitTunnelListCache. Исключение — .manual и
// .file: там текст ввёл сам пользователь, он мелкий и восстановить его неоткуда.
struct SplitTunnelConfig: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case exclude   // перечисленное идёт мимо VPN
        case include   // через VPN идёт ТОЛЬКО перечисленное
        var id: String { rawValue }

        var title: String {
            switch self {
            case .exclude: return "Исключения"
            case .include: return "Включения"
            }
        }

        var hint: String {
            switch self {
            case .exclude: return "Перечисленные подсети идут напрямую, мимо VPN. Весь остальной трафик — через VPN."
            case .include: return "Через VPN идут только перечисленные подсети. Весь остальной трафик — напрямую."
            }
        }
    }

    var enabled: Bool = false
    var mode: Mode = .exclude
    var sources: [SplitTunnelSource] = []

    var activeSources: [SplitTunnelSource] { sources.filter(\.isEnabled) }

    // Режим включений на пустом списке означает «через VPN не идёт ничего»:
    // комплемент пустого набора — 0.0.0.0/0, то есть весь трафик мимо VPN.
    // Такую конфигурацию не сохраняем и не применяем (см. SplitTunnelResolver).
    var isUnsafeIncludeSetup: Bool {
        enabled && mode == .include && activeSources.isEmpty
    }
}

struct SplitTunnelSource: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case preset   // вшитый список, url известен заранее
        case url      // произвольная ссылка
        case file     // импортированный файл, содержимое в body
        case manual   // введено руками, содержимое в body

        var title: String {
            switch self {
            case .preset: return "пресет"
            case .url: return "ссылка"
            case .file: return "файл"
            case .manual: return "вручную"
            }
        }

        var isRemote: Bool { self == .preset || self == .url }
    }

    var id: UUID = UUID()
    var kind: Kind
    var name: String
    var presetID: String?
    var url: String?
    var body: String?
    var isEnabled: Bool = true
}
