import Foundation
@testable import FreeTurnProxy

// Тестовый двойник NetworkPath (план, фаза 2.1/2.2): реальный NWPathMonitor
// непроверяем в юнит-тестах, а поведение вроде «смена интерфейса даёт
// немедленный реконнект» требует детерминированного управления путём.
final class MockNetworkPath: NetworkPathProviding {
    private(set) var activateCalled = false
    private(set) var deactivateCalled = false
    private var snapshot = NetworkPathSnapshot(isSatisfied: true, interfaceIndex: 1)
    private var handlers: [UUID: (NetworkPathSnapshot) -> Void] = [:]

    var currentSnapshot: NetworkPathSnapshot { snapshot }

    func activate() { activateCalled = true }
    func deactivate() { deactivateCalled = true }

    @discardableResult
    func addObserver(_ handler: @escaping (NetworkPathSnapshot) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    // Подсовывает новый путь всем подписчикам синхронно — ProxyManager сам
    // не уходит на фоновую очередь при обработке колбэка.
    func simulate(_ snapshot: NetworkPathSnapshot) {
        self.snapshot = snapshot
        for handler in handlers.values { handler(snapshot) }
    }
}
