import XCTest
@testable import FreeTurnProxy

final class LocalWGConfigFactoryTests: XCTestCase {
    func test_make_generatesDistinctServerAndClientKeys() {
        let config = LocalWGConfigFactory.make()
        XCTAssertNotEqual(config.serverPrivateKey, config.clientPrivateKey)
        XCTAssertNotEqual(config.serverPublicKey, config.clientPublicKey)
        XCTAssertFalse(config.serverPrivateKey.isEmpty)
        XCTAssertFalse(config.clientPrivateKey.isEmpty)
    }

    func test_make_withoutNameOrPort_usesDefaults() {
        let config = LocalWGConfigFactory.make()
        XCTAssertTrue(config.name.hasPrefix("freeturn-"))
        XCTAssertEqual(config.name.count, "freeturn-".count + 4)
        XCTAssertEqual(config.port, LocalWGConfig.defaultPort)
    }

    func test_make_replacingExisting_reusesNameAndPort() {
        let existing = LocalWGConfigFactory.make(name: "my-config", port: 51821)
        let replaced = LocalWGConfigFactory.make(existing: existing)
        XCTAssertEqual(replaced.name, "my-config")
        XCTAssertEqual(replaced.port, 51821)
        XCTAssertNotEqual(replaced.serverPrivateKey, existing.serverPrivateKey, "перегенерация должна давать новые ключи")
    }

    func test_randomName_hasExpectedShape() {
        let name = LocalWGConfigFactory.randomName()
        XCTAssertTrue(name.hasPrefix("freeturn-"))
        XCTAssertEqual(name.count, "freeturn-".count + 4)
    }
}
