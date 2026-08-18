import Foundation

// Вшитые источники, предлагаемые при добавлении: белый список РФ (тот же URL,
// что и у AllowedIPsBuilder.buildWithoutWhitelist) и два независимых списка
// заблокированного в РФ. Два — намеренно: antifilter.download сам бывает
// недоступен из РФ без VPN, GitHub-зеркало Re-filter — запасной вариант.
enum SplitTunnelPresets {
    struct Preset {
        let id: String
        let name: String
        let url: URL
        let defaultMode: SplitTunnelConfig.Mode
    }

    static let ruWhitelistURL = AllowedIPsBuilder.whitelistURL

    static let all: [Preset] = [
        Preset(id: "ru-whitelist", name: "Белые списки РФ",
               url: ruWhitelistURL, defaultMode: .exclude),
        Preset(id: "ru-blocked-antifilter", name: "Заблокированное в РФ (antifilter)",
               url: URL(string: "https://antifilter.download/list/allyouneed.lst")!,
               defaultMode: .include),
        Preset(id: "ru-blocked-refilter", name: "Заблокированное в РФ (Re-filter)",
               url: URL(string: "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ipsum.lst")!,
               defaultMode: .include),
    ]

    static func preset(id: String) -> Preset? { all.first { $0.id == id } }

    static func source(for preset: Preset) -> SplitTunnelSource {
        SplitTunnelSource(kind: .preset, name: preset.name, presetID: preset.id, url: preset.url.absoluteString)
    }
}
