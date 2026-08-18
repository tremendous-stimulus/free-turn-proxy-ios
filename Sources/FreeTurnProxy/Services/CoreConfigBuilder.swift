import Foundation

// Единственная точка сборки CoreConfig из SavedConfig + список VK-ссылок.
// Через неё идут и TunnelController.connect(), и ProxyManager.startMobile/
// restartMobile — чтобы правила заполнения (какие поля дефолтные, чем
// заменяется пустой clientId) не разъезжались между вызывающими.
enum CoreConfigBuilder {
    static func build(config c: SavedConfig, links: [String]) -> CoreConfig {
        var cc = CoreConfig(
            peer: c.peer,
            clientId: c.clientId.isEmpty ? ClientIdentity.current : c.clientId
        )

        cc.turn.transport = c.transport
        if !c.turnHost.isEmpty { cc.turn.host = c.turnHost }
        if !c.turnPort.isEmpty { cc.turn.port = c.turnPort }
        if c.threads > 0 { cc.turn.n = c.threads }

        if !c.listen.isEmpty { cc.proxy.listen = c.listen }

        cc.vk.links = links
        cc.vk.manualCaptcha = c.manualCaptcha
        if c.streamsPerCred > 0 { cc.vk.streamsPerCred = c.streamsPerCred }

        cc.obf.profile = c.obfProfile
        cc.obf.key = c.obfKey
        cc.obf.timingMs = c.obfTimingMs

        cc.dns.mode = c.dnsMode
        let dnsServers = c.dns.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !dnsServers.isEmpty { cc.dns.servers = dnsServers }

        cc.log.debug = c.debug

        return cc
    }
}
