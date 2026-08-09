import Foundation

// Codable-зеркало internal/config.ClientJSON@v2.1.1 (mobile/api.go: ParseClientJSON,
// mobile.go: startLocked). Декодер ядра стоит на DisallowUnknownFields() — лишнее
// или переименованное поле здесь валит старт туннеля в рантайме, а не на сборке
// (см. CoreConfigTests: схема сверяется полем в полe с internal/config/json.go).
//
// Дефолты в nested-структурах повторяют internal/config/defaults.go — мы всегда
// шлём JSON целиком, слияния с дефолтами ядра (как для CLI) для нас нет.
struct CoreConfig: Codable, Equatable {
    var peer: String
    var clientId: String
    var subUrl: String = ""
    var provider: String = "vk"
    var routes: Bool = false

    var turn = Turn()
    var proxy = Proxy()
    var vk = VK()
    var obf = Obf()
    var dns = DNS()
    var log = Log()
    var tunnel = Tunnel()

    struct Turn: Codable, Equatable {
        var n: Int = 10
        var transport: String = "tcp"
        var host: String = ""
        var port: String = ""
    }

    struct Proxy: Codable, Equatable {
        var mode: String = "udp"
        var bond: Bool = false
        var listen: String = "127.0.0.1:9000"
    }

    struct VK: Codable, Equatable {
        var links: [String] = []
        var streamsPerCred: Int = 10
        var manualCaptcha: Bool = false
        var platform: String = "mobile"
    }

    struct Obf: Codable, Equatable {
        var profile: String = "none"
        var key: String = ""
        var timingMs: Int = 0
    }

    struct DNS: Codable, Equatable {
        var mode: String = "auto"
        var servers: [String] = []
    }

    struct Log: Codable, Equatable {
        var debug: Bool = false
    }

    // tunnel.mode остаётся "none": свой WireGuard-туннель в приложении
    // недоступен без энтайтлмента packet-tunnel-provider (нет под сайдлоад).
    struct Tunnel: Codable, Equatable {
        var mode: String = "none"
        var config: String = ""
        var mtu: Int = 0
    }

    func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
