import XCTest
@testable import FreeTurnProxy

final class AllowedIPsBuilderTests: XCTestCase {

    // MARK: – parseCIDR

    func test_parseCIDR_basic() {
        let r = AllowedIPsBuilder.parseCIDR("10.0.0.0/8")
        XCTAssertEqual(r?.start, 10 << 24)
        XCTAssertEqual(r?.end, (10 << 24) + 0x00FF_FFFF)
    }

    func test_parseCIDR_singleHost() {
        let r = AllowedIPsBuilder.parseCIDR("1.2.3.4/32")
        let ip: UInt32 = (1<<24) | (2<<16) | (3<<8) | 4
        XCTAssertEqual(r?.start, ip)
        XCTAssertEqual(r?.end, ip)
    }

    func test_parseCIDR_wholeSpace() {
        let r = AllowedIPsBuilder.parseCIDR("0.0.0.0/0")
        XCTAssertEqual(r?.start, 0)
        XCTAssertEqual(r?.end, 0xFFFF_FFFF)
    }

    func test_parseCIDR_rejectsJunk() {
        XCTAssertNil(AllowedIPsBuilder.parseCIDR("not a cidr"))
        XCTAssertNil(AllowedIPsBuilder.parseCIDR("1.2.3/8"))
        XCTAssertNil(AllowedIPsBuilder.parseCIDR("1.2.3.4"))
    }

    // MARK: – parseCIDRs (массив строк → диапазоны)

    func test_parseCIDRs_multiline() {
        let text = """
        10.0.0.0/8
        192.168.0.0/16
        # это коммент с CIDR-подобной 999.999/8 не сматчится
        172.16.0.0/12
        """
        let ranges = AllowedIPsBuilder.parseCIDRs(text)
        XCTAssertEqual(ranges.count, 3)
    }

    func test_parseCIDRs_skipsInvalidOctets() {
        XCTAssertTrue(AllowedIPsBuilder.parseCIDRs("999.999.999.999/8").isEmpty)
        XCTAssertTrue(AllowedIPsBuilder.parseCIDRs("1.2.3.4/40").isEmpty)
    }

    // MARK: – range

    func test_range_prefix0_isWhole() {
        let r = AllowedIPsBuilder.range(ip: 12345, prefix: 0)
        XCTAssertEqual(r.start, 0)
        XCTAssertEqual(r.end, 0xFFFF_FFFF)
    }

    func test_range_prefix32_isSingleHost() {
        let r = AllowedIPsBuilder.range(ip: 12345, prefix: 32)
        XCTAssertEqual(r.start, 12345)
        XCTAssertEqual(r.end, 12345)
    }

    func test_range_alignsDownToPrefixBoundary() {
        // 10.1.2.3/8 — должно стянуться к 10.0.0.0..10.255.255.255
        let ip: UInt32 = (10<<24) | (1<<16) | (2<<8) | 3
        let r = AllowedIPsBuilder.range(ip: ip, prefix: 8)
        XCTAssertEqual(r.start, 10 << 24)
        XCTAssertEqual(r.end, (10 << 24) + 0x00FF_FFFF)
    }

    // MARK: – merge

    func test_merge_empty() {
        XCTAssertTrue(AllowedIPsBuilder.merge([]).isEmpty)
    }

    func test_merge_disjointPreserved() {
        let a = AllowedIPsBuilder.IPRange(start: 0, end: 10)
        let b = AllowedIPsBuilder.IPRange(start: 100, end: 200)
        XCTAssertEqual(AllowedIPsBuilder.merge([a, b]), [a, b])
    }

    func test_merge_overlappingCombined() {
        let a = AllowedIPsBuilder.IPRange(start: 0, end: 100)
        let b = AllowedIPsBuilder.IPRange(start: 50, end: 150)
        XCTAssertEqual(AllowedIPsBuilder.merge([a, b]),
                       [AllowedIPsBuilder.IPRange(start: 0, end: 150)])
    }

    func test_merge_adjacentCombined() {
        let a = AllowedIPsBuilder.IPRange(start: 0, end: 99)
        let b = AllowedIPsBuilder.IPRange(start: 100, end: 200)
        XCTAssertEqual(AllowedIPsBuilder.merge([a, b]),
                       [AllowedIPsBuilder.IPRange(start: 0, end: 200)])
    }

    func test_merge_sortsBeforeJoining() {
        let a = AllowedIPsBuilder.IPRange(start: 50, end: 60)
        let b = AllowedIPsBuilder.IPRange(start: 10, end: 20)
        let merged = AllowedIPsBuilder.merge([a, b])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, 10)
        XCTAssertEqual(merged[1].start, 50)
    }

    // MARK: – complement

    func test_complement_emptyExcludes_isWhole() {
        XCTAssertEqual(AllowedIPsBuilder.complement(of: []), ["0.0.0.0/0"])
    }

    func test_complement_wholeSpace_isEmpty() {
        let whole = AllowedIPsBuilder.IPRange(start: 0, end: 0xFFFF_FFFF)
        XCTAssertTrue(AllowedIPsBuilder.complement(of: [whole]).isEmpty)
    }

    func test_complement_minus10_8_givesExpectedPrefixSet() {
        let r = AllowedIPsBuilder.parseCIDR("10.0.0.0/8")!
        let got = AllowedIPsBuilder.complement(of: [r])
        XCTAssertEqual(got, [
            "0.0.0.0/5",
            "8.0.0.0/7",
            "11.0.0.0/8",
            "12.0.0.0/6",
            "16.0.0.0/4",
            "32.0.0.0/3",
            "64.0.0.0/2",
            "128.0.0.0/1",
        ])
    }

    func test_complement_resultDoesNotIntersectExcludes() {
        let excludes = [
            AllowedIPsBuilder.parseCIDR("10.0.0.0/8")!,
            AllowedIPsBuilder.parseCIDR("192.168.0.0/16")!,
            AllowedIPsBuilder.parseCIDR("127.0.0.0/8")!,
        ]
        let gaps = AllowedIPsBuilder.complement(of: excludes)
        let gapRanges = gaps.compactMap(AllowedIPsBuilder.parseCIDR)
        for g in gapRanges {
            for e in excludes {
                XCTAssertFalse(
                    !(g.end < e.start || g.start > e.end),
                    "gap \(g) пересекается с exclude \(e)"
                )
            }
        }
    }

    // MARK: – appendPrefixes

    func test_appendPrefixes_singleAlignedBlock() {
        var out: [String] = []
        // 10.0.0.0 .. 10.255.255.255 ровно один блок /8
        AllowedIPsBuilder.appendPrefixes(start: 10 << 24,
                                         end: (10 << 24) + 0x00FF_FFFF,
                                         into: &out)
        XCTAssertEqual(out, ["10.0.0.0/8"])
    }

    func test_appendPrefixes_singleHost() {
        var out: [String] = []
        AllowedIPsBuilder.appendPrefixes(start: 1, end: 1, into: &out)
        XCTAssertEqual(out, ["0.0.0.1/32"])
    }

    // MARK: – cidr

    func test_cidr_formats() {
        XCTAssertEqual(AllowedIPsBuilder.cidr(0, 0), "0.0.0.0/0")
        XCTAssertEqual(AllowedIPsBuilder.cidr(0xFFFF_FFFF, 32), "255.255.255.255/32")
        XCTAssertEqual(AllowedIPsBuilder.cidr((10<<24) | (0<<16) | (0<<8) | 0, 8), "10.0.0.0/8")
    }

    // MARK: – build(.fullInternet) — публичный API, безопасный (не лезет в сеть)

    func test_build_fullInternet_isWholeSpace() async throws {
        let s = try await AllowedIPsBuilder.build(scheme: .fullInternet)
        XCTAssertEqual(s, "0.0.0.0/0")
    }
}
