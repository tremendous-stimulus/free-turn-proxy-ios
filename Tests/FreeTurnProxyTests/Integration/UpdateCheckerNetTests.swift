import XCTest
@testable import FreeTurnProxy

final class UpdateCheckerNetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.register()
    }

    override func tearDown() {
        MockURLProtocol.unregister()
        super.tearDown()
    }

    private func appsJSON(version: String) -> Data {
        Data(#"{"apps":[{"version":"\#(version)","downloadURL":"x"}]}"#.utf8)
    }

    func test_newerVersion_returned() async {
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .http(status: 200, body: appsJSON(version: "999.0.0"))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertEqual(result, "999.0.0")
    }

    func test_olderVersion_nil() async {
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .http(status: 200, body: appsJSON(version: "0.0.1"))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertNil(result)
    }

    func test_emptyApps_nil() async {
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .http(status: 200, body: Data(#"{"apps":[]}"#.utf8))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertNil(result)
    }

    func test_serverError_nil() async {
        // Даже на 404 URLSession.data вернёт данные с этим статусом — но они
        // не парсятся как json → guard вернёт nil.
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .http(status: 404, body: Data("not found".utf8))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertNil(result)
    }

    func test_networkError_nil() async {
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .error(URLError(.notConnectedToInternet))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertNil(result)
    }

    func test_malformedJSON_nil() async {
        MockURLProtocol.stub(
            urlContains: "apps.json",
            with: .http(status: 200, body: Data("not json".utf8))
        )
        let result = await UpdateChecker.fetchLatestVersion()
        XCTAssertNil(result)
    }
}
