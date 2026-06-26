import Foundation

// URLProtocol-сабкласс для перехвата URLSession.shared. Использование:
//   MockURLProtocol.register()
//   MockURLProtocol.stub(host: "api.example.com", status: 200, body: data)
//   // выполнить тестируемый код
//   MockURLProtocol.reset()
//   MockURLProtocol.unregister()
final class MockURLProtocol: URLProtocol {

    // Ответ на конкретный запрос: либо HTTP-ответ, либо сетевая ошибка.
    enum Stub {
        case http(status: Int, body: Data, headers: [String: String] = [:])
        case error(Error)
    }

    // Матчер по запросу: возвращает Stub или nil если не подходит.
    typealias Matcher = (URLRequest) -> Stub?

    private static var matchers: [Matcher] = []
    private static let lock = NSLock()

    // MARK: – Контроль регистрации

    static func register() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    static func unregister() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        reset()
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        matchers.removeAll()
    }

    // MARK: – Регистрация stub'ов

    // По полному совпадению URL.
    static func stub(url: URL, with stub: Stub) {
        addMatcher { req in req.url == url ? stub : nil }
    }

    // По хосту (host == "api.vk.com").
    static func stub(host: String, with stub: Stub) {
        addMatcher { req in req.url?.host == host ? stub : nil }
    }

    // По части пути (urlContains("calls.start")).
    static func stub(urlContains needle: String, with stub: Stub) {
        addMatcher { req in
            (req.url?.absoluteString.contains(needle) ?? false) ? stub : nil
        }
    }

    // Общий матчер.
    static func addMatcher(_ m: @escaping Matcher) {
        lock.lock(); defer { lock.unlock() }
        matchers.append(m)
    }

    // MARK: – URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return matchers.contains { $0(request) != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub: Stub = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            for m in Self.matchers {
                if let s = m(self.request) { return s }
            }
            // canInit вернул true — матчер обязан найтись. Сюда не должны попасть.
            return .error(URLError(.unknown))
        }()

        switch stub {
        case .http(let status, let body, let headers):
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .error(let err):
            client?.urlProtocol(self, didFailWithError: err)
        }
    }

    override func stopLoading() {}
}
