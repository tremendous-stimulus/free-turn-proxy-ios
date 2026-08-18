import Foundation
import Network

// Снимок системного пути сети — уже без типов Network.framework, чтобы
// потребители (ProxyManager, тесты) не тянули за собой NWPath. isSatisfied —
// есть ли вообще связность; interfaceIndex — индекс текущего физического
// интерфейса (см. SocketProtector.physicalIndex, .other/utun сюда не попадает).
struct NetworkPathSnapshot: Equatable {
    var isSatisfied: Bool
    var interfaceIndex: UInt32

    static let unknown = NetworkPathSnapshot(isSatisfied: false, interfaceIndex: 0)
}

// Подписка на изменения пути. NetworkPath (класс ниже) — прод-реализация
// поверх NWPathMonitor; тесты подставляют свой мок вместо реального системного
// монитора (план, фаза 2.1/2.2 — "смена индекса интерфейса даёт немедленный
// реконнект без бекоффа" непроверяема на живом NWPathMonitor).
protocol NetworkPathProviding: AnyObject {
    var currentSnapshot: NetworkPathSnapshot { get }
    func activate()
    func deactivate()
    @discardableResult
    func addObserver(_ handler: @escaping (NetworkPathSnapshot) -> Void) -> UUID
    func removeObserver(_ id: UUID)
}

// Единственный NWPathMonitor на всё приложение (план, фаза 2.1). Раньше он
// жил только внутри SocketProtector и обслуживал исключительно выбор
// IP_BOUND_IF; теперь SocketProtector — такой же потребитель, как
// ProxyManager, второй монитор не заводится.
final class NetworkPath: NetworkPathProviding {
    static let shared = NetworkPath()

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkPath.monitor")
    private let lock = NSLock()
    private var snapshot = NetworkPathSnapshot.unknown

    private struct Observer {
        let id: UUID
        let handler: (NetworkPathSnapshot) -> Void
    }
    private var observers: [Observer] = []

    private init() {}

    var currentSnapshot: NetworkPathSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    // NWPathMonitor одноразовый: после cancel() его нельзя запустить снова,
    // поэтому на каждый activate заводим новый — иначе после первого же
    // stop()/start() туннеля индекс перестал бы обновляться. Идемпотентна:
    // и SocketProtector, и ProxyManager зовут её независимо на своём пути
    // старта.
    func activate() {
        lock.lock()
        guard monitor == nil else { lock.unlock(); return }
        let fresh = NWPathMonitor()
        monitor = fresh
        lock.unlock()

        fresh.pathUpdateHandler = { [weak self] path in
            self?.handle(path)
        }
        fresh.start(queue: queue)
    }

    func deactivate() {
        lock.lock()
        let stale = monitor
        monitor = nil
        snapshot = .unknown
        lock.unlock()
        stale?.cancel()
    }

    @discardableResult
    func addObserver(_ handler: @escaping (NetworkPathSnapshot) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        observers.append(Observer(id: id, handler: handler))
        lock.unlock()
        return id
    }

    func removeObserver(_ id: UUID) {
        lock.lock()
        observers.removeAll { $0.id == id }
        lock.unlock()
    }

    private func handle(_ path: NWPath) {
        let next = NetworkPathSnapshot(
            isSatisfied: path.status == .satisfied,
            interfaceIndex: SocketProtector.physicalIndex(in: path)
        )
        lock.lock()
        snapshot = next
        let toNotify = observers
        lock.unlock()

        // pathUpdateHandler зовётся с приватной очереди монитора; и UI-стейт
        // ProxyManager, и NSLock-геттеры выше не рассчитаны на конкурентный
        // доступ с неё.
        DispatchQueue.main.async {
            for observer in toNotify { observer.handler(next) }
        }
    }
}
