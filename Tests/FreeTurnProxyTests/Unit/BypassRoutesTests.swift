import XCTest
@testable import FreeTurnProxy

final class BypassRoutesTests: XCTestCase {
    func test_network_masksHostBits() {
        XCTAssertEqual(BypassRoutes.network(of: "10.8.0.2/24"), "10.8.0.0/24")
        XCTAssertEqual(BypassRoutes.network(of: "192.168.1.130/25"), "192.168.1.128/25")
        XCTAssertEqual(BypassRoutes.network(of: "172.16.5.9/12"), "172.16.0.0/12")
    }

    func test_network_bareAddressIsSingleHost() {
        XCTAssertEqual(BypassRoutes.network(of: "10.8.0.2"), "10.8.0.2/32")
    }

    func test_network_edgePrefixes() {
        XCTAssertEqual(BypassRoutes.network(of: "1.2.3.4/0"), "0.0.0.0/0")
        XCTAssertEqual(BypassRoutes.network(of: "1.2.3.4/32"), "1.2.3.4/32")
    }

    func test_network_malformedIsNil() {
        XCTAssertNil(BypassRoutes.network(of: "не-адрес"))
        XCTAssertNil(BypassRoutes.network(of: "10.8.0.2/33"))
        XCTAssertNil(BypassRoutes.network(of: "10.8.0.300/24"))
        XCTAssertNil(BypassRoutes.network(of: "10.8.0/24"))
    }

    // Address в конфиге может быть списком — исключить надо каждую сеть,
    // иначе часть трафика к собственному серверу уйдёт мимо туннеля.
    func test_excludes_handlesMultipleAddresses() {
        XCTAssertEqual(
            BypassRoutes.excludes(address: "10.8.0.2/24, 192.168.9.5/30"),
            ["10.8.0.0/24", "192.168.9.4/30"]
        )
    }

    // Сеть VPN-сервера обязана попасть в исключения — она приватная и иначе
    // была бы перехвачена общим правилом «приватное мимо туннеля».
    func test_excludes_coversPrivateRangeUsedByTunnel() throws {
        let excluded = BypassRoutes.excludes(address: "10.8.0.2/24")
        XCTAssertTrue(BypassRoutes.privateCIDRs.contains("10.0.0.0/8"))
        XCTAssertEqual(excluded, ["10.8.0.0/24"])
    }

    func test_network_ipv6_masksToPrefix() {
        XCTAssertEqual(BypassRoutes.network(of: "fd00::2/64"), "fd00::/64")
        XCTAssertEqual(BypassRoutes.network(of: "fd00::2"), "fd00::2/128")
        XCTAssertNil(BypassRoutes.network(of: "fd00::2/129"))
    }

    func test_excludes_ipv6Address_isNotDropped() {
        XCTAssertEqual(
            BypassRoutes.excludes(address: "fd00::2/128", dns: "fd00::1"),
            ["fd00::2/128", "fd00::1/128"]
        )
    }

    // Типовой конфиг WG даёт host-префикс, и сеть из него не выводится: без
    // отдельного исключения DNS резолвер туннеля (10.8.0.1) уходил бы мимо
    // туннеля под общее правило «приватное — мимо», то есть DNS не работал бы
    // вовсе.
    func test_excludes_hostPrefixAddress_stillCoversTunnelDNS() {
        XCTAssertEqual(
            BypassRoutes.excludes(address: "10.8.0.2/32", dns: "10.8.0.1"),
            ["10.8.0.2/32", "10.8.0.1/32"]
        )
    }

    func test_excludes_multipleDNS_deduplicates() {
        XCTAssertEqual(
            BypassRoutes.excludes(address: "10.8.0.2/32", dns: "10.8.0.1, 10.8.0.2, 1.1.1.1"),
            ["10.8.0.2/32", "10.8.0.1/32", "1.1.1.1/32"]
        )
    }

    // Префикс у DNS исключать по подсети нельзя: это адрес резолвера, а не
    // сеть, и /24 утащил бы в туннель лишнее.
    func test_excludes_dnsWithPrefix_narrowedToHost() {
        XCTAssertEqual(
            BypassRoutes.excludes(address: "", dns: "10.8.0.1/24"),
            ["10.8.0.1/32"]
        )
    }

    // current() обязан отдавать список без единого сетевого запроса: фетч на
    // пути старта локальной половины давал дедлок (тонул в ещё не поднятом
    // туннеле) и задерживал её на ~58 секунд.
    func test_current_withoutCache_usesFallbackAndPrivateRanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BypassRoutesTests.empty"))
        defaults.removePersistentDomain(forName: "BypassRoutesTests.empty")
        let routes = BypassRoutes.current(defaults: defaults)
        XCTAssertEqual(routes, BypassRoutes.privateCIDRs + AllowedIPsBuilder.vkFallbackCIDRs)
    }

    func test_current_prefersCachedVKRanges() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BypassRoutesTests.cached"))
        defaults.removePersistentDomain(forName: "BypassRoutesTests.cached")
        defaults.set(["87.240.128.0/18"], forKey: DefaultsKeys.bypassVKCIDRs)
        XCTAssertEqual(BypassRoutes.current(defaults: defaults),
                       BypassRoutes.privateCIDRs + ["87.240.128.0/18"])
    }
}
