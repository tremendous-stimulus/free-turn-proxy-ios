import Foundation

// Сохранённая конфигурация TURN-сервера. VK-ссылки не храним здесь — они
// общие для всех конфигураций и берутся из ManualLinks (вкладка «Туннель»).
// Пустые dns/listen/turnHost/... означают дефолт ядра.
struct SavedConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var peer: String
    var obfKey: String = ""
    var dns: String = ""
    var listen: String = ""
    var transport: String = "udp"
    // Всегда решать VK captcha вручную (через WebView), минуя авто-решатель.
    var manualCaptcha: Bool = false

    var obfProfile: String = "none"        // none | rtpopus | rtpopus2 | rtpopus3
    var obfTimingMs: Int = 0               // -obf-timing, значим только при mode == "udp"
    var mode: String = "udp"               // proxy.mode: udp (WireGuard) | tcp (Xray)
    var bond: Bool = false                 // значим только при mode == "tcp"
    var threads: Int = 0                   // -n, 0 = дефолт ядра
    var streamsPerCred: Int = 0            // 0 = дефолт ядра
    var dnsMode: String = "auto"           // auto | plain | doh
    var turnHost: String = ""              // альтернативный TURN-узел
    var turnPort: String = ""
    var debug: Bool = false
    var clientId: String = ""              // непустой = cid, пришедший из freeturn://-ссылки

    init(id: UUID = UUID(), name: String, peer: String, obfKey: String = "", dns: String = "",
         listen: String = "", transport: String = "udp", manualCaptcha: Bool = false,
         obfProfile: String? = nil, obfTimingMs: Int = 0, mode: String = "udp", bond: Bool = false,
         threads: Int = 0, streamsPerCred: Int = 0, dnsMode: String = "auto", turnHost: String = "",
         turnPort: String = "", debug: Bool = false, clientId: String = "") {
        self.id = id
        self.name = name
        self.peer = peer
        self.obfKey = obfKey
        self.dns = dns
        self.listen = listen
        self.transport = transport
        self.manualCaptcha = manualCaptcha
        // Если профиль не задан явно, повторяем поведение старого v1.8.0-биндинга:
        // непустой ключ подразумевал rtpopus.
        self.obfProfile = obfProfile ?? (obfKey.isEmpty ? "none" : "rtpopus")
        self.obfTimingMs = obfTimingMs
        self.mode = mode
        self.bond = bond
        self.threads = threads
        self.streamsPerCred = streamsPerCred
        self.dnsMode = dnsMode
        self.turnHost = turnHost
        self.turnPort = turnPort
        self.debug = debug
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, peer, obfKey, dns, listen, transport, manualCaptcha,
             obfProfile, obfTimingMs, mode, bond, threads, streamsPerCred,
             dnsMode, turnHost, turnPort, debug, clientId
    }

    // Записи, сохранённые до Этапа B, не знают про новые поля —
    // synthesized Codable подставил бы им дефолт obfProfile == "none",
    // молча выключив обфускацию для пользователей, у которых уже был задан
    // ключ. Ручной init(from:) сохраняет прежнее поведение для таких записей.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        peer = try c.decode(String.self, forKey: .peer)
        obfKey = try c.decodeIfPresent(String.self, forKey: .obfKey) ?? ""
        dns = try c.decodeIfPresent(String.self, forKey: .dns) ?? ""
        listen = try c.decodeIfPresent(String.self, forKey: .listen) ?? ""
        transport = try c.decodeIfPresent(String.self, forKey: .transport) ?? "udp"
        manualCaptcha = try c.decodeIfPresent(Bool.self, forKey: .manualCaptcha) ?? false
        if let profile = try c.decodeIfPresent(String.self, forKey: .obfProfile) {
            obfProfile = profile
        } else {
            obfProfile = obfKey.isEmpty ? "none" : "rtpopus"
        }
        obfTimingMs = try c.decodeIfPresent(Int.self, forKey: .obfTimingMs) ?? 0
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "udp"
        bond = try c.decodeIfPresent(Bool.self, forKey: .bond) ?? false
        threads = try c.decodeIfPresent(Int.self, forKey: .threads) ?? 0
        streamsPerCred = try c.decodeIfPresent(Int.self, forKey: .streamsPerCred) ?? 0
        dnsMode = try c.decodeIfPresent(String.self, forKey: .dnsMode) ?? "auto"
        turnHost = try c.decodeIfPresent(String.self, forKey: .turnHost) ?? ""
        turnPort = try c.decodeIfPresent(String.self, forKey: .turnPort) ?? ""
        debug = try c.decodeIfPresent(Bool.self, forKey: .debug) ?? false
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId) ?? ""
    }
}
