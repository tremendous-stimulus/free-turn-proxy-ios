import Foundation
import Mobile
@testable import FreeTurnProxy

final class MockFtunAPI: FtunAPI {
    var startCalled = false
    var startCallCount = 0
    var stopCallCount = 0
    var startError: Error?
    var lastConfigJSON: String?
    var eventSinkSet: FtunEventSinkProtocol?

    var localUp = false
    var localHandshakeAgeSec: Int64 = 0

    func start(configJSON: String) throws {
        startCalled = true
        startCallCount += 1
        lastConfigJSON = configJSON
        if let err = startError { throw err }
    }

    func stop() {
        stopCallCount += 1
    }

    func stats() -> FtunSnapshot? {
        let s = FtunSnapshot()
        s.localUp = localUp
        s.localHandshakeAgeSec = localHandshakeAgeSec
        return s
    }

    func setEventSink(_ s: FtunEventSinkProtocol?) { eventSinkSet = s }

    func version() -> String { "mock" }
}
