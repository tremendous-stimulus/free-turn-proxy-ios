import XCTest
@testable import FreeTurnProxy

// ManualLinks стоит на UserDefaults.standard (общий пул ссылок для всех
// сохранённых конфигураций, как и раньше был manualLink) — подчищаем оба
// ключа вокруг каждого теста, чтобы не тянуть состояние между тестами.
final class ManualLinksTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.manualLink)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.manualLinks)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.manualLink)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.manualLinks)
        super.tearDown()
    }

    func test_current_emptyByDefault() {
        XCTAssertEqual(ManualLinks.current, [])
    }

    func test_setAndGet_roundTrips() {
        ManualLinks.current = ["https://vk.com/call/join/a", "https://vk.com/call/join/b"]
        XCTAssertEqual(ManualLinks.current, ["https://vk.com/call/join/a", "https://vk.com/call/join/b"])
    }

    func test_migratesLegacySingleLink() {
        UserDefaults.standard.set("https://vk.com/call/join/legacy", forKey: DefaultsKeys.manualLink)
        XCTAssertEqual(ManualLinks.current, ["https://vk.com/call/join/legacy"])
    }

    func test_migrationIsOneShot_newValueWins() {
        UserDefaults.standard.set("https://vk.com/call/join/legacy", forKey: DefaultsKeys.manualLink)
        _ = ManualLinks.current  // triggers migration
        ManualLinks.current = []
        XCTAssertEqual(ManualLinks.current, [], "после явной записи миграция не должна снова подставлять старую ссылку")
    }
}
