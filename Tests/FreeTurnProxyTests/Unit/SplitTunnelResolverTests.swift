import XCTest
@testable import FreeTurnProxy

final class SplitTunnelResolverTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SplitTunnelResolverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // Отключено — поведение не должно отличаться от старого BypassRoutes.current().
    func test_disabled_matchesBypassRoutesCurrent() {
        let cfg = SplitTunnelConfig()
        let got = SplitTunnelResolver.bypassCIDRs(for: cfg, defaults: defaults)
        XCTAssertEqual(got, BypassRoutes.current(defaults: defaults))
    }

    func test_excludeMode_appendsUserCIDRsToBypassRoutesCurrent() {
        var cfg = SplitTunnelConfig()
        cfg.enabled = true
        cfg.mode = .exclude
        cfg.sources = [SplitTunnelSource(kind: .manual, name: "m", body: "1.2.3.0/24")]

        let got = SplitTunnelResolver.bypassCIDRs(for: cfg, defaults: defaults)
        let base = BypassRoutes.current(defaults: defaults)
        XCTAssertEqual(Set(got), Set(base + ["1.2.3.0/24"]))
    }

    func test_includeMode_isComplementOfUserRanges() {
        var cfg = SplitTunnelConfig()
        cfg.enabled = true
        cfg.mode = .include
        // Публичная подсеть, не пересекающаяся ни с приватными диапазонами,
        // ни с VK fallback — иначе BypassRoutes.current() (он всегда
        // домешивается сверху) замаскировал бы результат комплемента.
        cfg.sources = [SplitTunnelSource(kind: .manual, name: "m", body: "8.8.0.0/16")]

        let got = SplitTunnelResolver.bypassCIDRs(for: cfg, defaults: defaults)
        let ranges = got.compactMap(AllowedIPsBuilder.parseCIDR)
        func covered(_ ip: String) -> Bool {
            let v = AllowedIPsBuilder.parseCIDR("\(ip)/32")!.start
            return ranges.contains { $0.start <= v && v <= $0.end }
        }
        // Включённая подсеть идёт через VPN — в bypass её быть не должно.
        XCTAssertFalse(covered("8.8.5.5"))
        // Остальной публичный интернет — мимо VPN.
        XCTAssertTrue(covered("1.2.3.4"))
    }

    // Пустой список включений — предохранитель: не должны отдать 0.0.0.0/0.
    func test_includeMode_emptySources_fallsBackToBypassRoutesCurrent() {
        var cfg = SplitTunnelConfig()
        cfg.enabled = true
        cfg.mode = .include
        cfg.sources = []

        let got = SplitTunnelResolver.bypassCIDRs(for: cfg, defaults: defaults)
        XCTAssertFalse(got.contains("0.0.0.0/0"))
        XCTAssertEqual(got, BypassRoutes.current(defaults: defaults))
    }

    // Отключённые (но присутствующие) источники не должны участвовать в подсчёте.
    func test_disabledSourceIsIgnored() {
        var cfg = SplitTunnelConfig()
        cfg.enabled = true
        cfg.mode = .exclude
        cfg.sources = [SplitTunnelSource(kind: .manual, name: "m", body: "1.2.3.0/24", isEnabled: false)]

        let got = SplitTunnelResolver.bypassCIDRs(for: cfg, defaults: defaults)
        XCTAssertEqual(got, BypassRoutes.current(defaults: defaults))
    }

    func test_isUnsafeIncludeSetup_flagsEmptyIncludeList() {
        var cfg = SplitTunnelConfig()
        cfg.enabled = true
        cfg.mode = .include
        XCTAssertTrue(cfg.isUnsafeIncludeSetup)

        cfg.sources = [SplitTunnelSource(kind: .manual, name: "m", body: "1.2.3.0/24")]
        XCTAssertFalse(cfg.isUnsafeIncludeSetup)

        cfg.mode = .exclude
        cfg.sources = []
        XCTAssertFalse(cfg.isUnsafeIncludeSetup)
    }
}
