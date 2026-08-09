import Foundation

// Формат share-ссылки freeturn://<base64url(json)> — зеркало internal/uri в
// Go-апстриме (docs/uri.md). VK-ссылка на звонок (-link) в URI не входит,
// она уникальна для каждого клиента и вводится получателем отдельно.
enum FreeturnLinkError: LocalizedError, Equatable {
    case invalidScheme
    case emptyPayload
    case invalidBase64
    case invalidJSON
    case unsupportedVersion
    case missingProvider
    case missingPeer

    var errorDescription: String? {
        switch self {
        case .invalidScheme:      return "Ссылка должна начинаться с freeturn://"
        case .emptyPayload:       return "Пустая ссылка"
        case .invalidBase64:      return "Повреждённая ссылка"
        case .invalidJSON:        return "Повреждённая ссылка"
        case .unsupportedVersion: return "Ссылка более новой версии — обновите приложение"
        case .missingProvider:    return "В ссылке не указан provider"
        case .missingPeer:        return "В ссылке не указан адрес сервера"
        }
    }
}

enum FreeturnLink {
    static let scheme = "freeturn"
    private static let currentVersion = 1

    // JSON-схема payload — короткие ключи как в Go internal/uri.wire.
    // wg — нестандартное поле Android-клиента (текст WG-конфига), мы его
    // только принимаем, сами не генерируем.
    private struct Wire: Codable {
        var v: Int
        var provider: String
        var peer: String
        var transport: String = ""
        var mode: String = ""
        var bond: Bool = false
        var obf: String = ""
        var key: String = ""
        var n: Int = 0
        var spc: Int = 0
        var cid: String = ""
        var listen: String = ""
        var dns: String = ""
        var dnss: String = ""
        var mcap: Bool = false
        var name: String = ""
        var wg: String?

        // Синтезированный init(from:) требует все ключи, даже те, у которых
        // есть значение по умолчанию — "пустые и дефолтные поля опускаются"
        // (docs/uri.md) означает, что декодер обязан их не требовать. Ручной
        // init(from:) отменяет автогенерируемый memberwise-init, поэтому он
        // тоже прописан явно — используется при кодировании исходящей ссылки.
        init(v: Int, provider: String, peer: String, transport: String = "", mode: String = "",
             bond: Bool = false, obf: String = "", key: String = "", n: Int = 0, spc: Int = 0,
             cid: String = "", listen: String = "", dns: String = "", dnss: String = "",
             mcap: Bool = false, name: String = "", wg: String? = nil) {
            self.v = v
            self.provider = provider
            self.peer = peer
            self.transport = transport
            self.mode = mode
            self.bond = bond
            self.obf = obf
            self.key = key
            self.n = n
            self.spc = spc
            self.cid = cid
            self.listen = listen
            self.dns = dns
            self.dnss = dnss
            self.mcap = mcap
            self.name = name
            self.wg = wg
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v)
            provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
            peer = try c.decodeIfPresent(String.self, forKey: .peer) ?? ""
            transport = try c.decodeIfPresent(String.self, forKey: .transport) ?? ""
            mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
            bond = try c.decodeIfPresent(Bool.self, forKey: .bond) ?? false
            obf = try c.decodeIfPresent(String.self, forKey: .obf) ?? ""
            key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
            n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
            spc = try c.decodeIfPresent(Int.self, forKey: .spc) ?? 0
            cid = try c.decodeIfPresent(String.self, forKey: .cid) ?? ""
            listen = try c.decodeIfPresent(String.self, forKey: .listen) ?? ""
            dns = try c.decodeIfPresent(String.self, forKey: .dns) ?? ""
            dnss = try c.decodeIfPresent(String.self, forKey: .dnss) ?? ""
            mcap = try c.decodeIfPresent(Bool.self, forKey: .mcap) ?? false
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            wg = try c.decodeIfPresent(String.self, forKey: .wg)
        }
    }

    // MARK: – Разбор

    // Принимает полную ссылку ("freeturn://...") либо голый payload.
    static func parse(_ s: String, defaultName: String) throws -> SavedConfig {
        let payload: String
        if s.hasPrefix("\(scheme)://") {
            payload = String(s.dropFirst("\(scheme)://".count))
        } else {
            throw FreeturnLinkError.invalidScheme
        }
        guard !payload.isEmpty else { throw FreeturnLinkError.emptyPayload }
        guard let data = base64URLDecode(payload) else { throw FreeturnLinkError.invalidBase64 }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else {
            throw FreeturnLinkError.invalidJSON
        }
        guard w.v == currentVersion else { throw FreeturnLinkError.unsupportedVersion }
        guard !w.provider.isEmpty else { throw FreeturnLinkError.missingProvider }
        guard !w.peer.isEmpty else { throw FreeturnLinkError.missingPeer }

        return SavedConfig(
            name: w.name.isEmpty ? defaultName : w.name,
            peer: w.peer,
            obfKey: w.key,
            dns: w.dnss,
            listen: w.listen,
            transport: w.transport.isEmpty ? "udp" : w.transport,
            manualCaptcha: w.mcap,
            obfProfile: w.obf.isEmpty ? "none" : w.obf,
            mode: w.mode.isEmpty ? "udp" : w.mode,
            bond: w.bond,
            threads: w.n,
            streamsPerCred: w.spc,
            dnsMode: w.dns.isEmpty ? "auto" : w.dns,
            clientId: w.cid
        )
    }

    // MARK: – Генерация

    // cid не проставляем — это механизм allowlist владельца сервера, мы им не
    // пользуемся; wg тоже не генерируем, WG-конфиг у нас отдельный поток.
    static func encode(config c: SavedConfig, provider: String = "vk", name: String = "") -> String {
        let w = Wire(
            v: currentVersion,
            provider: provider,
            peer: c.peer,
            transport: c.transport,
            mode: c.mode,
            bond: c.bond,
            obf: c.obfProfile == "none" ? "" : c.obfProfile,
            key: c.obfProfile == "none" ? "" : c.obfKey,
            n: c.threads,
            spc: c.streamsPerCred,
            listen: c.listen,
            dns: c.dnsMode,
            dnss: c.dns,
            mcap: c.manualCaptcha,
            name: name
        )
        guard let data = try? JSONEncoder().encode(w) else { return "" }
        return "\(scheme)://\(base64URLEncode(data))"
    }

    // MARK: – base64url (RFC 4648 §5, без padding)

    private static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
