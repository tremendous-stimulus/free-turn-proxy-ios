import Foundation
import Mobile

// Прокладка над gomobile-биндингом golib/ftun (локальная терминация
// WG-in-WG, план vpn-lexical-rossum.md, фаза 1). Единственная точка вызова
// Ftun* — по образцу Services/MobileAPI.swift. Прод — LiveFtunAPI, тесты —
// собственный мок.
//
// import Mobile, не Ftun: ftun собирается ОДНИМ gomobile bind вместе с
// апстрим-пакетом mobile в общий Mobile.xcframework — раздельная сборка
// зашивает каждому пакету свой Go-рантайм, и когда оба реально исполняются
// в одном процессе, это падает с SIGSEGV (см. план, «Фаза 1.5 — блокер»,
// Makefile: framework). Классы Ftun* при этом остаются в этом же модуле —
// биндинг сохраняет имена по исходному Go-пакету независимо от того, что
// физически всё в одном .xcframework.
protocol FtunAPI {
    func start(configJSON: String) throws
    func stop()
    func stats() -> FtunSnapshot?
    func setEventSink(_ s: FtunEventSinkProtocol?)
    func version() -> String
}

// Зеркало golib/ftun.StartConfig (device.go) — camelCase совпадает с
// json-тегами Go-структуры без явных CodingKeys, как у CoreConfig.
struct FtunStartRequest: Codable {
    var remoteConf: String
    var localPrivateKey: String
    var localPeerPublicKey: String
    var relayAddr: String
    var listenPort: Int
    var mtu: Int

    func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

struct LiveFtunAPI: FtunAPI {
    func start(configJSON: String) throws {
        var err: NSError?
        FtunStart(configJSON, &err)
        if let err { throw err }
    }

    func stop() {
        FtunStop()
    }

    func stats() -> FtunSnapshot? {
        FtunStats()
    }

    func setEventSink(_ s: FtunEventSinkProtocol?) {
        FtunSetEventSink(s)
    }

    func version() -> String {
        FtunVersion()
    }
}
