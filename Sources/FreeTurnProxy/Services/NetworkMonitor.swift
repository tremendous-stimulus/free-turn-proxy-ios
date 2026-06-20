import Network

// Следит за сменой активного сетевого пути (LTE↔Wi-Fi, кратковременная потеря
// и восстановление связи). При роуминге UDP-сокеты прокси к TURN-серверам,
// привязанные к старому интерфейсу, умирают молча — поэтому ловим смену пути
// и дёргаем onChange, чтобы вызывающий переподключил туннель.
final class NetworkMonitor {
    var onChange: (() -> Void)?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.freeturn.netmonitor")
    // Подпись пути: статус + основной интерфейс. Реконнектим только когда она
    // реально меняется, иначе NWPathMonitor засыпал бы лишними срабатываниями.
    private var lastSignature: String?

    func start() {
        stop()
        lastSignature = nil
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in self?.handle(path) }
        m.start(queue: queue)
        monitor = m
    }

    // NWPathMonitor нельзя перезапускать после cancel — пересоздаём в start().
    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    private func handle(_ path: NWPath) {
        let sig = Self.signature(path)
        // Первый апдейт после старта — это базовая линия, не реконнект.
        guard let prev = lastSignature else {
            lastSignature = sig
            return
        }
        guard sig != prev else { return }
        lastSignature = sig
        // Реконнектим только когда есть рабочий путь; на «нет связи» ждём.
        if path.status == .satisfied {
            onChange?()
        }
    }

    private static func signature(_ path: NWPath) -> String {
        let primary = path.availableInterfaces.first.map { "\($0.type)" } ?? "none"
        return "\(path.status)|\(primary)"
    }
}
