import XCTest
@testable import FreeTurnProxy

@MainActor
final class ConfigStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // Уникальный suite, чтобы тесты не делили состояние.
        suiteName = "test.configstore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func sample(_ name: String, peer: String = "1.2.3.4:5") -> SavedConfig {
        SavedConfig(name: name, peer: peer)
    }

    // MARK: – Базовый CRUD

    func test_add_makesItSelected() {
        let store = ConfigStore(defaults: defaults)
        let a = sample("A")
        store.add(a)
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.selectedID, a.id)
        XCTAssertEqual(store.selected?.name, "A")
    }

    func test_update_replacesByID() {
        let store = ConfigStore(defaults: defaults)
        let a = sample("A")
        store.add(a)
        var modified = a
        modified.name = "A renamed"
        store.update(modified)
        XCTAssertEqual(store.configs.first?.name, "A renamed")
        XCTAssertEqual(store.configs.count, 1)
    }

    func test_delete_movesSelectionAndStacksUndo() {
        let store = ConfigStore(defaults: defaults)
        let a = sample("A"), b = sample("B")
        store.add(a)
        store.add(b)
        XCTAssertEqual(store.selectedID, b.id)
        store.delete(b)
        XCTAssertEqual(store.configs.count, 1)
        XCTAssertEqual(store.selectedID, a.id)
        XCTAssertEqual(store.lastDeleted?.config.id, b.id)
    }

    func test_undoDelete_restoresAtSameIndex() {
        let store = ConfigStore(defaults: defaults)
        let a = sample("A"), b = sample("B"), c = sample("C")
        store.add(a); store.add(b); store.add(c)
        store.delete(b)
        XCTAssertEqual(store.configs.map(\.name), ["A", "C"])
        store.undoDelete()
        XCTAssertEqual(store.configs.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(store.selectedID, b.id)
        XCTAssertNil(store.lastDeleted)
    }

    // MARK: – Persist

    func test_persistAndReload_keepsConfigsAndSelection() {
        do {
            let store = ConfigStore(defaults: defaults)
            let a = sample("A")
            let b = sample("B")
            store.add(a)
            store.add(b)
            store.select(a.id)
        }
        // Новый instance из того же defaults.
        let reloaded = ConfigStore(defaults: defaults)
        XCTAssertEqual(reloaded.configs.map(\.name), ["A", "B"])
        XCTAssertEqual(reloaded.selected?.name, "A")
    }

    // MARK: – migrateLegacy

    func test_migrateLegacy_singleManualConfigImported() {
        defaults.set("1.2.3.4:5", forKey: "manualPeer")
        defaults.set("deadbeef", forKey: "manualObfKey")
        defaults.set("8.8.8.8", forKey: "manualDns")
        defaults.set("127.0.0.1:9000", forKey: "manualListen")
        defaults.set("tcp", forKey: "manualTransport")

        let store = ConfigStore(defaults: defaults)
        XCTAssertEqual(store.configs.count, 1)
        let cfg = store.configs.first!
        XCTAssertEqual(cfg.name, "Моя конфигурация")
        XCTAssertEqual(cfg.peer, "1.2.3.4:5")
        XCTAssertEqual(cfg.obfKey, "deadbeef")
        XCTAssertEqual(cfg.transport, "tcp")
    }

    func test_migrateLegacy_skippedWhenNoPeer() {
        let store = ConfigStore(defaults: defaults)
        XCTAssertTrue(store.configs.isEmpty)
    }
}
