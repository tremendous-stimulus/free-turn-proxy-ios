import XCTest
@testable import FreeTurnProxy

final class AllowedIPsBuilderNetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.register()
    }

    override func tearDown() {
        MockURLProtocol.unregister()
        super.tearDown()
    }

    // MARK: – withoutWhitelist

    func test_withoutWhitelist_200_returnsNonEmptyAndExcludesWhitelisted() async throws {
        let whitelist = """
        10.0.0.0/8
        87.240.0.0/16
        """
        MockURLProtocol.stub(host: "raw.githubusercontent.com",
                             with: .http(status: 200, body: Data(whitelist.utf8)))

        let result = try await AllowedIPsBuilder.build(scheme: .withoutWhitelist)
        XCTAssertFalse(result.isEmpty)

        // 10.0.0.0/8 (из whitelist) не должен быть в результате — а вот 11.0.0.0/8 должен.
        XCTAssertFalse(result.contains("10.0.0.0/8"))
        XCTAssertTrue(result.contains("11.0.0.0/8"))
    }

    func test_withoutWhitelist_500_throwsFetch() async {
        MockURLProtocol.stub(host: "raw.githubusercontent.com",
                             with: .http(status: 500, body: Data()))
        do {
            _ = try await AllowedIPsBuilder.build(scheme: .withoutWhitelist)
            XCTFail("expected throw")
        } catch AllowedIPsBuilder.BuildError.fetch {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func test_withoutWhitelist_networkError_throwsFetch() async {
        MockURLProtocol.stub(host: "raw.githubusercontent.com",
                             with: .error(URLError(.notConnectedToInternet)))
        do {
            _ = try await AllowedIPsBuilder.build(scheme: .withoutWhitelist)
            XCTFail("expected throw")
        } catch AllowedIPsBuilder.BuildError.fetch {
            // ok
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    // MARK: – withoutVK

    func test_withoutVK_RIPE_200_excludesRIPEPrefixes() async throws {
        let ripeJSON = #"""
        {
          "data": {
            "prefixes": [
              { "prefix": "87.240.0.0/16" },
              { "prefix": "5.61.16.0/20" }
            ]
          }
        }
        """#
        MockURLProtocol.stub(host: "stat.ripe.net",
                             with: .http(status: 200, body: Data(ripeJSON.utf8)))

        let result = try await AllowedIPsBuilder.build(scheme: .withoutVK)
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains("87.240.0.0/16"))
    }

    func test_withoutVK_RIPE_500_fallbackUsed() async throws {
        MockURLProtocol.stub(host: "stat.ripe.net",
                             with: .http(status: 500, body: Data()))

        // Fallback не пуст → результат должен сгенерироваться без ошибки.
        let result = try await AllowedIPsBuilder.build(scheme: .withoutVK)
        XCTAssertFalse(result.isEmpty)
    }

    func test_withoutVK_emptyRIPE_fallbackUsed() async throws {
        let emptyRIPE = Data(#"{"data":{"prefixes":[]}}"#.utf8)
        MockURLProtocol.stub(host: "stat.ripe.net",
                             with: .http(status: 200, body: emptyRIPE))

        let result = try await AllowedIPsBuilder.build(scheme: .withoutVK)
        XCTAssertFalse(result.isEmpty)
    }
}
