import XCTest
@testable import FreeTurnProxy

final class LaunchStateTests: XCTestCase {

    private func defaults(_ name: String) throws -> UserDefaults {
        let d = try XCTUnwrap(UserDefaults(suiteName: "LaunchStateTests.\(name)"))
        d.removePersistentDomain(forName: "LaunchStateTests.\(name)")
        return d
    }

    func test_isUpgradedUser_defaultsToNil() throws {
        let d = try defaults("fresh")
        XCTAssertNil(LaunchState.isUpgradedUser(defaults: d))
    }

    func test_resolve_withoutConfigs_setsFalse() throws {
        let d = try defaults("noConfigs")
        XCTAssertFalse(LaunchState.resolveUpgradedUser(hasConfigs: false, defaults: d))
        XCTAssertEqual(LaunchState.isUpgradedUser(defaults: d), false)
    }

    func test_resolve_withConfigs_setsTrue() throws {
        let d = try defaults("withConfigs")
        XCTAssertTrue(LaunchState.resolveUpgradedUser(hasConfigs: true, defaults: d))
        XCTAssertEqual(LaunchState.isUpgradedUser(defaults: d), true)
    }

    // Главное свойство: считаем один раз. Пользователь, закрывший подсказку,
    // не должен получить её снова просто потому, что профили на месте.
    func test_resolve_doesNotOverwriteDismissedFalse() throws {
        let d = try defaults("dismissed")
        LaunchState.setUpgradedUser(true, defaults: d)
        LaunchState.setUpgradedUser(false, defaults: d)   // крестик на подсказке
        XCTAssertFalse(LaunchState.resolveUpgradedUser(hasConfigs: true, defaults: d))
        XCTAssertEqual(LaunchState.isUpgradedUser(defaults: d), false)
    }

    // И наоборот: удаление всех профилей после первого запуска не превращает
    // обновившегося пользователя в новичка.
    func test_resolve_keepsTrue_whenConfigsLaterDisappear() throws {
        let d = try defaults("emptied")
        LaunchState.resolveUpgradedUser(hasConfigs: true, defaults: d)
        XCTAssertTrue(LaunchState.resolveUpgradedUser(hasConfigs: false, defaults: d))
    }

    func test_recordRun_returnsPreviousVersionAndStoresCurrent() throws {
        let d = try defaults("version")
        XCTAssertNil(LaunchState.recordRun(version: "1.2.0", defaults: d))
        XCTAssertEqual(LaunchState.lastRunVersion(defaults: d), "1.2.0")
        XCTAssertEqual(LaunchState.recordRun(version: "1.3.0", defaults: d), "1.2.0")
        XCTAssertEqual(LaunchState.lastRunVersion(defaults: d), "1.3.0")
    }
}
