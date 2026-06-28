import XCTest
@testable import FreeTurnProxy

@MainActor
final class TunnelViewModelTests: XCTestCase {

    private static let vkAPI = "api.vk.com"
    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        super.tearDown()
    }

    // Создаём VM с указанным токеном напрямую — Keychain в тестах не используем:
    // iOS Simulator Keychain ненадёжен в CI-окружении (GitHub Actions).
    private func vm(token: String? = nil) -> TunnelViewModel {
        let v = TunnelViewModel(session: mockSession)
        v.vkAuthToken = token
        return v
    }

    // MARK: – createCall без токена

    func test_createCall_noToken_showsVKWebFallback() async {
        let vm = vm()
        await vm.createCall()
        XCTAssertTrue(vm.showVKWebFallback)
        XCTAssertNil(vm.errorText)
    }

    // MARK: – createCall с токеном

    func test_createCall_success_setsLink() async {
        let body = #"{"response":{"join_link":"https://vk.com/call/join/xyz"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))

        let vm = vm(token: "faketoken")
        await vm.createCall()
        XCTAssertEqual(vm.link, "https://vk.com/call/join/xyz")
        XCTAssertNil(vm.errorText)
    }

    func test_createCall_apiError5_clearsTokenAndShowsFallback() async {
        let body = #"{"error":{"error_code":5,"error_msg":"User authorization failed"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))

        let vm = vm(token: "expiredtoken")
        await vm.createCall()
        XCTAssertTrue(vm.showVKWebFallback)
        XCTAssertNil(vm.vkAuthToken)
    }

    func test_createCall_networkError_setsErrorText_keepToken() async {
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .error(URLError(.notConnectedToInternet)))

        let vm = vm(token: "mytoken")
        await vm.createCall()
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.showVKWebFallback)
        XCTAssertEqual(vm.vkAuthToken, "mytoken")
    }
}
