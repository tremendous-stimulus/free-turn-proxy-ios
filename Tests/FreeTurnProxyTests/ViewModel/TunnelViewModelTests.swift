import XCTest
@testable import FreeTurnProxy

@MainActor
final class TunnelViewModelTests: XCTestCase {

    private static let vkAPI = "api.vk.com"
    private var mockSession: URLSession!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockSession = MockURLProtocol.makeSession()
        ManualLinks.current = []
        suiteName = "test.tunnelviewmodel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        mockSession = nil
        ManualLinks.current = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // Создаём VM с указанным токеном напрямую — Keychain в тестах не используем:
    // iOS Simulator Keychain ненадёжен в CI-окружении (GitHub Actions). Store —
    // на изолированном UserDefaults, не ConfigStore.shared, чтобы тесты не
    // трогали реальные сохранённые конфигурации пользователя.
    private func vm(token: String? = nil, store: ConfigStore? = nil) -> TunnelViewModel {
        let v = TunnelViewModel(session: mockSession, store: store ?? ConfigStore(defaults: defaults))
        v.vkAuthToken = token
        return v
    }

    // MARK: – generateLinkBatch без токена

    func test_generateLinkBatch_noToken_showsVKWebFallback() async {
        let vm = vm()
        let result = await vm.generateLinkBatch(count: 1)
        XCTAssertNil(result)
        XCTAssertTrue(vm.showVKWebFallback)
        XCTAssertNil(vm.errorText)
    }

    // MARK: – generateLinkBatch с токеном

    func test_generateLinkBatch_success_returnsLinks() async {
        let body = #"{"response":{"join_link":"https://vk.com/call/join/xyz"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))

        let vm = vm(token: "faketoken")
        let result = await vm.generateLinkBatch(count: 1)
        XCTAssertEqual(result, ["https://vk.com/call/join/xyz"])
        XCTAssertNil(vm.errorText)
        XCTAssertTrue(vm.links.isEmpty, "generateLinkBatch не трогает links сама по себе — это делает вызывающая сторона")
    }

    func test_generateLinkBatch_respectsCount() async {
        let body = #"{"response":{"join_link":"https://vk.com/call/join/xyz"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))

        let vm = vm(token: "faketoken")
        let result = await vm.generateLinkBatch(count: 3)
        XCTAssertEqual(result?.count, 3)
    }

    func test_generateLinkBatch_apiError5_clearsTokenAndShowsFallback() async {
        let body = #"{"error":{"error_code":5,"error_msg":"User authorization failed"}}"#
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .http(status: 200, body: Data(body.utf8)))

        let vm = vm(token: "expiredtoken")
        let result = await vm.generateLinkBatch(count: 1)
        XCTAssertNil(result)
        XCTAssertTrue(vm.showVKWebFallback)
        XCTAssertNil(vm.vkAuthToken)
    }

    func test_generateLinkBatch_networkError_setsErrorText_keepToken() async {
        MockURLProtocol.stub(host: Self.vkAPI,
                             with: .error(URLError(.notConnectedToInternet)))

        let vm = vm(token: "mytoken")
        let result = await vm.generateLinkBatch(count: 1)
        XCTAssertNil(result)
        XCTAssertNotNil(vm.errorText)
        XCTAssertFalse(vm.showVKWebFallback)
        XCTAssertEqual(vm.vkAuthToken, "mytoken")
    }

    // MARK: – canConnect

    func test_canConnect_false_whenNoConfigSelected() {
        let vm = vm()
        XCTAssertFalse(vm.canConnect)
    }

    func test_canConnect_false_whenNoLinksGenerated() {
        let store = ConfigStore(defaults: defaults)
        let vm = vm(store: store)
        store.add(SavedConfig(name: "test", peer: "1.2.3.4:5"))
        XCTAssertFalse(vm.canConnect)
    }

    func test_canConnect_true_whenLinksPresentAndPeerValid() {
        let store = ConfigStore(defaults: defaults)
        let vm = vm(store: store)
        store.add(SavedConfig(name: "test", peer: "1.2.3.4:5"))
        vm.links = ["https://vk.com/call/join/a"]
        XCTAssertTrue(vm.canConnect)
    }
}
