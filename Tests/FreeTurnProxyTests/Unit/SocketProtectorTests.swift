import XCTest
@testable import FreeTurnProxy

final class SocketProtectorTests: XCTestCase {
    private let protector = SocketProtector.shared

    override func tearDown() {
        protector.deactivate()
        super.tearDown()
    }

    func test_protect_onRealSocket_succeeds() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertTrue(protector.protect(Int(fd)))
    }

    // Невалидный дескриптор — обе опции обязаны провалиться, и это единственный
    // случай, когда protect честно возвращает false.
    func test_protect_invalidDescriptor_fails() {
        XCTAssertFalse(protector.protect(-1))
    }

    // activate/deactivate зовутся из start/stop туннеля, в том числе повторно
    // после реконнекта — оба обязаны быть идемпотентны.
    func test_activateAndDeactivate_areIdempotent() {
        protector.activate()
        protector.activate()
        protector.deactivate()
        protector.deactivate()
    }
}
