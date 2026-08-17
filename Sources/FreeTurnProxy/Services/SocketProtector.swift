import Foundation
import Network
import Mobile

// Выводит сокеты Go-ядра из-под системного VPN: без этого при включённом
// AmneziaWG весь трафик приложения (TURN, VK-авторизация, DNS) уходит в utun →
// в наш же ftun-responder → во внешнюю половину, которая ещё не поднята. Чтобы
// поднять туннель, нужен туннель — дедлок (см. план vpn-lexical-rossum.md,
// фаза 5.1; воспроизведён логами от 2026-08-17).
//
// Апстрим для этого уже держит крючок: mobile.SetProtect вешает наш колбэк на
// Control каждого исходящего net.Dialer, включая DNS-путь (internal/client/dnsdial
// подменяет и net.DefaultResolver). Патчить ядро не нужно.
//
// Работоспособность привязки перепроверена на устройстве 2026-08-18 (Фаза 0-бис):
// и на Wi-Fi, и на LTE сокет с IP_BOUND_IF выходит мимо туннеля. Вывод
// оригинальной Фазы 0 («не работает») неверен.
// Один класс на оба биндинга: у mobile.Protector и ftun.Protector совпадает
// селектор, поэтому и сокеты ядра, и сокеты обходного netstack'а (фаза 5.2)
// защищает одна и та же реализация.
final class SocketProtector: NSObject, MobileProtectorProtocol, FtunProtectorProtocol {
    static let shared = SocketProtector()

    // IP_BOUND_IF / IPV6_BOUND_IF не экспортированы в Swift — сырые значения
    // из <netinet/in.h> и <netinet6/in6.h>.
    private static let ipBoundIf: Int32 = 25
    private static let ipv6BoundIf: Int32 = 125

    // NWPathMonitor одноразовый: после cancel() его нельзя запустить снова,
    // поэтому на каждый activate заводим новый — иначе после первого же
    // stop()/start() туннеля индекс перестал бы обновляться.
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "SocketProtector.path")
    private let lock = NSLock()
    private var interfaceIndex: UInt32 = 0

    private override init() { super.init() }

    // Индекс интерфейса обязан быть свежим: protect() зовётся на каждый новый
    // сокет, и после перехода LTE↔Wi-Fi устаревшее значение привязало бы сокет
    // к мёртвому интерфейсу. Поэтому не разовое чтение, а подписка на путь.
    func activate() {
        lock.lock()
        guard monitor == nil else { lock.unlock(); return }
        let fresh = NWPathMonitor()
        monitor = fresh
        lock.unlock()

        fresh.pathUpdateHandler = { [weak self] path in
            self?.updateIndex(from: path)
        }
        fresh.start(queue: queue)
    }

    func deactivate() {
        lock.lock()
        let stale = monitor
        monitor = nil
        interfaceIndex = 0
        lock.unlock()
        stale?.cancel()
    }

    // MARK: - MobileProtectorProtocol

    // Возвращаем true и когда привязывать не к чему: false заставил бы ядро
    // считать сокет непригодным, хотя без VPN он прекрасно работает.
    func protect(_ fd: Int) -> Bool {
        lock.lock()
        var index = interfaceIndex
        lock.unlock()
        if index == 0 {
            index = Self.fallbackIndex()
        }
        guard index != 0 else { return true }

        let fd32 = Int32(fd)
        // Домен сокета не выясняем: «чужая» опция просто вернёт ошибку, это
        // дешевле, чем getsockopt(SO_DOMAIN) ради выбора одной из двух.
        let v4 = setsockopt(fd32, IPPROTO_IP, Self.ipBoundIf, &index, socklen_t(MemoryLayout<UInt32>.size))
        let v6 = setsockopt(fd32, IPPROTO_IPV6, Self.ipv6BoundIf, &index, socklen_t(MemoryLayout<UInt32>.size))
        return v4 == 0 || v6 == 0
    }

    // MARK: - Выбор интерфейса

    private func updateIndex(from path: Network.NWPath) {
        let index = Self.physicalIndex(in: path)
        lock.lock()
        interfaceIndex = index
        lock.unlock()
    }

    // availableInterfaces упорядочен по предпочтительности, поэтому берём
    // первый физический. Тип .other — это как раз utun самого VPN, его
    // пропускаем: привязка к нему вернула бы нас в туннель.
    static func physicalIndex(in path: Network.NWPath) -> UInt32 {
        for iface in path.availableInterfaces {
            switch iface.type {
            case .wifi, .cellular, .wiredEthernet:
                return if_nametoindex(iface.name)
            default:
                continue
            }
        }
        return 0
    }

    // Подписка могла ещё не отдать первый путь к моменту первого dial — тогда
    // спрашиваем систему напрямую по общепринятым именам.
    private static func fallbackIndex() -> UInt32 {
        for name in ["en0", "pdp_ip0"] {
            let index = if_nametoindex(name)
            if index != 0 { return index }
        }
        return 0
    }
}
