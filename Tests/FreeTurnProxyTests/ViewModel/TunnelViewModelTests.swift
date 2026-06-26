import XCTest
@testable import FreeTurnProxy

@MainActor
final class TunnelViewModelTests: XCTestCase {

    private static let vkAPI = "api.vk.com"

    // URLSession с MockURLProtocol в protocolClasses — не зависит от registerClass.
    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        mockSession = MockURLProtocol.makeSession()
        Keychain.remove(Keychain.vkTokenAccount)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        Keychain.remove(Keychain.vkTokenAccount)
        super.tearDown()
    }

    private func vm() -> TunnelViewModel { TunnelViewModel(session: mockSession) }

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
        Keychain.set("faketoken", for: Keychain.vkTokenAccount)

        let vm = vm()
        await vm.createCall()
        XCTAssertEqual(vm.link, "https://vk.com/call/join/xyz")
        XCTAssertNil(vm.errorText)
    }

    func test_createCall_apiError5_clearsTokenAndShowsFallback() async {
        let body = #"{"error":{"error_code":5,"error_msg":"User authorization failed"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))
        Keychain.set("expiredtoken", for: Keychain.vkTokenAccount)

        let vm = vm()
        await vm.createCall()
        XCTAssertTrue(vm.showVKWebFallback)
        XCTAssertNil(Keychain.get(Keychain.vkTokenAccount))
    }

    func test_createCall_networkError_setsErrorText_keepToken() async {
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .error(URLError(.notConnectedToInternet)))
        Keychain.set("mytoken", for: Keychain.vkTokenAccount)

        let vm = vm()
        await vm.createCall()
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.showVKWebFallback)
        XCTAssertEqual(Keychain.get(Keychain.vkTokenAccount), "mytoken")
    }
}
