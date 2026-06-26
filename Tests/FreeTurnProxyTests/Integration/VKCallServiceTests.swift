import XCTest
@testable import FreeTurnProxy

final class VKCallServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.register()
    }

    override func tearDown() {
        MockURLProtocol.unregister()
        super.tearDown()
    }

    func test_success_returnsJoinLink() async throws {
        let body = Data(#"{"response":{"join_link":"https://vk.com/call/join/abc"}}"#.utf8)
        MockURLProtocol.stub(host: "api.vk.com", with: .http(status: 200, body: body))

        let link = try await vkCreateCall(token: "tkn")
        XCTAssertEqual(link, "https://vk.com/call/join/abc")
    }

    func test_apiError_code5_thrown() async {
        let body = Data(#"{"error":{"error_code":5,"error_msg":"User auth failed"}}"#.utf8)
        MockURLProtocol.stub(host: "api.vk.com", with: .http(status: 200, body: body))

        do {
            _ = try await vkCreateCall(token: "tkn")
            XCTFail("expected throw")
        } catch VKCallError.apiError(let code, let msg) {
            XCTAssertEqual(code, 5)
            XCTAssertEqual(msg, "User auth failed")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_responseWithoutJoinLink_throwsNoLink() async {
        let body = Data(#"{"response":{}}"#.utf8)
        MockURLProtocol.stub(host: "api.vk.com", with: .http(status: 200, body: body))

        do {
            _ = try await vkCreateCall(token: "tkn")
            XCTFail("expected throw")
        } catch VKCallError.noLink {
            // ok
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_networkError_thrown() async {
        MockURLProtocol.stub(
            host: "api.vk.com",
            with: .error(URLError(.notConnectedToInternet))
        )

        do {
            _ = try await vkCreateCall(token: "tkn")
            XCTFail("expected throw")
        } catch VKCallError.network {
            // ok
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
