import Foundation

// Runtime-конфигурация активного туннеля: сохранённая конфигурация сервера +
// список VK-ссылок (задаются отдельно от SavedConfig, см. TunnelController /
// ManualLinks). Единая точка сборки CoreConfig из этой пары — CoreConfigBuilder.
struct FreeTurnConfig {
    var config: SavedConfig
    var links: [String]

    var peer: String { config.peer }
}
