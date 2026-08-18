import Foundation
import Mobile
import UIKit
import UserNotifications

final class ProxyManager: ObservableObject {
    static let shared = ProxyManager()

    @Published var isRunning = false
    @Published var state: TunnelState = .idle
    @Published var connectedStreams: Int = 0
    @Published var totalStreams: Int = 0
    @Published var errorMessage: String = ""
    @Published var configFileName: String?

    // Статистика трафика — обновляется отдельным лёгким поллингом getState(),
    // потому что EventSink.onState байтовые счётчики не несёт (только стадию
    // и стримы). Состояние туннеля само по себе push-driven через onState.
    @Published var txTotalBytes: Int64 = 0
    @Published var rxTotalBytes: Int64 = 0
    @Published var txRateBytesPerSec: Int64 = 0
    @Published var rxRateBytesPerSec: Int64 = 0

    // Локальная половина дороги (план, фаза 2, WG-in-WG) — независимый от
    // внешнего state статус: реконнект external-половины её не трогает, см.
    // startLocalTunnelIfNeeded. Для старого режима (useLocalTunnel == false)
    // остаётся false/0, UI показывает только один статус, как раньше.
    @Published var localTunnelUp = false
    @Published var localTunnelHandshakeAgeSec: Int64 = 0
    // Внешняя половина WG-in-WG (план, фаза 2.6) — вход для зонда (2.5) и
    // для ступени 0 лестницы восстановления (nudge), которая чинит именно
    // эту половину.
    @Published var remoteTunnelUp = false
    @Published var remoteTunnelHandshakeAgeSec: Int64 = 0

    private var config: FreeTurnConfig?
    private var statsTimer: Timer?
    private var logShipTimer: Timer?   // ship unified buffer → worker (10s)
    private var probeTimer: Timer?     // зонд живости туннеля (5s)
    private var lastLoggedError = ""
    private let audio = AudioKeepAlive()
    private let mobile: MobileAPI
    private let ftun: FtunAPI
    private let localWGConfig: LocalWGConfigStoring
    private let externalWGConfig: ExternalWGConfigStoring
    private let networkPath: NetworkPathProviding

    private static let probeInterval: TimeInterval = 5
    private static let probeURL = URL(string: "http://captive.apple.com")!

    // WG-in-WG (план, фаза 2/5.3): локальный WG-responder слушает
    // 127.0.0.1:<порт из общего LocalWGConfig, дефолт 9001>, апстрим-релей —
    // на SavedConfig.listen (дефолт 127.0.0.1:9000, тот же, что и в старом
    // режиме). ftun поднимается один раз за сессию — после первого
    // connected — и не трогается реконнектом внешней половины.
    private var ftunStarted = false

    // Единственная очередь, с которой зовётся cgo-фасад ftun. Все три вызова
    // блокирующие: start поднимает два device.Device и gvisor-стек, stop ждёт
    // закрытия релеев, stats сериализует UAPI обоих девайсов — с главного
    // потока это хич при подключении и подвисший UI при отключении. Очередь
    // последовательная: порядок stop→start обязан сохраняться.
    private let ftunQueue: DispatchQueue
    private var ftunStatsInFlight = false

    private func relayAddr(for c: SavedConfig) -> String {
        let v = c.listen.trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? AppSettings.defaultListen : v
    }

    // Реконнект-цикл стартует из трёх мест, все идут через enterRetryCycle()
    // либо напрямую через triggerAutoReconnect(immediate:):
    //   • Go выдал error из connected (push через EventSink.onState);
    //   • healthcheck-зонд (captive.apple.com) провалился дважды подряд;
    //   • сменился физический интерфейс/появился путь после unsatisfied
    //     (handleNetworkPathChange, план фаза 2.2).
    // Раньше третий триггер был выпилен из-за ложных срабатываний на
    // включение AmneziaWG — оказалось, что SocketProtector.physicalIndex
    // намеренно пропускает utun (см. её комментарий), поэтому включение VPN
    // индекс физического интерфейса не меняет и старый повод для выпила не
    // действует.
    private let protector = SocketProtector.shared

    // Инжектируем, чтобы тесты не зависели от содержимого UserDefaults и файлов
    // кэша. Синхронная намеренно: сеть на пути старта локальной половины даёт
    // дедлок (см. startLocalTunnelIfNeeded) — SplitTunnelResolver сам читает
    // только то, что уже лежит на диске/в UserDefaults, в сеть не ходит.
    // bypassExcludeCIDRs сюда не входит — считается напрямую через
    // BypassRoutes.excludes, см. startLocalTunnelIfNeeded.
    private let bypassRoutes: (SplitTunnelConfig) -> [String]

    // Один и тот же зонд достижимости используют и обычный 5с-таймер
    // (performProbe), и подтверждение дешёвых ступеней лестницы
    // (confirmCheapStepOutcome) — вынесено в замыкание, чтобы тесты не
    // зависели от реальной сети (по образцу bypassRoutes выше).
    private let reachabilityProbe: (@escaping (Bool) -> Void) -> Void

    // Срабатывает только если в течение сессии хотя бы раз дошли до connected —
    // connecting→error не ретраит (это первичный провал коннекта, не реконнект).
    private var everConnected = false
    private var autoReconnectAttempt = 0
    private var autoReconnectWork: DispatchWorkItem?
    private var backoffTickTimer: Timer?
    // Стартует на первом входе в retry-цикл из connected, гасится:
    //   • на успешном переподключении (там же шлём «Переподключились»);
    //   • на тихом восстановлении после ступеней 0–1 (recoverSilently);
    //   • на stop()/start().
    // Никогда не гасится сдачей — план, фаза 2.4: бюджет попыток убран,
    // бекофф упирается в потолок 15с и продолжается бесконечно.
    private var inRetryCycle = false
    private let lostNotifID = "tunnel-lost"
    private let recoveredNotifID = "tunnel-recovered"

    // Лестница восстановления (план, фаза 2.3): чем дороже действие, тем реже
    // до него доходит. Ступени 0–1 не пересоздают Go-сессию — не тратят
    // capcha/переавторизацию, поэтому эскалация к ним не страшна.
    private enum RecoveryStep: String {
        case nudge, wake, restart, fullRestart
    }

    private func recoveryStep(forAttempt attempt: Int) -> RecoveryStep {
        switch min(attempt, 3) {
        case 0: return .nudge
        case 1: return .wake
        case 2: return .restart
        default: return .fullRestart
        }
    }

    // Зонд (2.5): не одиночный провал, а два подряд — таймаут ~4.5с на
    // плохом LTE иначе даёт ложняки на каждый пятый тик.
    private var probeFailureStreak = 0
    private var lastRxTotalAtProbe: Int64 = 0

    // Единственный источник смены физического интерфейса — подписка на
    // NetworkPath (план, фаза 2.1/2.2). 0 — путь ещё не отдал первый снимок.
    private var lastInterfaceIndex: UInt32 = 0
    private var networkPathObserverID: UUID?

    // Сколько секунд осталось до следующей попытки реконнекта. Обновляется раз
    // в секунду, чтобы UI мог показывать «Переподключаемся через X с».
    @Published var retryBackoffSeconds: Int = 0

    var serverAddress: String { config?.config.peer ?? "" }

    private static func liveReachabilityProbe(_ completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: probeURL)
        req.timeoutInterval = probeInterval - 0.5
        URLSession.shared.dataTask(with: req) { _, _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }.resume()
    }

    private init() {
        self.mobile = LiveMobileAPI()
        self.ftun = LiveFtunAPI()
        self.localWGConfig = KeychainLocalWGConfigStore()
        self.externalWGConfig = KeychainExternalWGConfigStore()
        self.bypassRoutes = { SplitTunnelResolver.bypassCIDRs(for: $0) }
        self.ftunQueue = DispatchQueue(label: "com.freeturn.proxy.ftun")
        self.networkPath = NetworkPath.shared
        self.reachabilityProbe = Self.liveReachabilityProbe
    }

    // Инжектируемый init — для тестов с MockMobileAPI/MockFtunAPI/MockNetworkPath.
    init(mobile: MobileAPI, ftun: FtunAPI = LiveFtunAPI(),
         localWGConfig: LocalWGConfigStoring = KeychainLocalWGConfigStore(),
         externalWGConfig: ExternalWGConfigStoring = KeychainExternalWGConfigStore(),
         bypassRoutes: @escaping (SplitTunnelConfig) -> [String] = { _ in [] },
         ftunQueue: DispatchQueue = DispatchQueue(label: "com.freeturn.proxy.ftun"),
         networkPath: NetworkPathProviding = NetworkPath.shared,
         reachabilityProbe: @escaping (@escaping (Bool) -> Void) -> Void = { $0(true) }) {
        self.mobile = mobile
        self.ftun = ftun
        self.localWGConfig = localWGConfig
        self.externalWGConfig = externalWGConfig
        self.bypassRoutes = bypassRoutes
        // Тест передаёт свою очередь, чтобы дождаться асинхронных вызовов ftun.
        self.ftunQueue = ftunQueue
        self.networkPath = networkPath
        // Дефолт для тестов — «всегда достижимо»: без него любой авто-ретрай
        // бил бы в реальную сеть. Тесты, которым нужен провал, подставляют
        // свой замыкание.
        self.reachabilityProbe = reachabilityProbe
    }

    func loadConfig(_ config: FreeTurnConfig, fileName: String) {
        self.config = config
        self.configFileName = fileName
    }

    func deleteConfig() {
        guard !isRunning else { return }
        config = nil
        configFileName = nil
    }

    func start() throws {
        guard let config else { throw AppError.noConfig }
        try audio.start()
        try startMobile(config)
        isRunning = true
        everConnected = false
        autoReconnectAttempt = 0
        autoReconnectWork?.cancel()
        autoReconnectWork = nil
        backoffTickTimer?.invalidate()
        backoffTickTimer = nil
        retryBackoffSeconds = 0
        inRetryCycle = false
        ftunStarted = false
        probeFailureStreak = 0
        lastRxTotalAtProbe = 0
        lastInterfaceIndex = networkPath.currentSnapshot.interfaceIndex
        networkPathObserverID = networkPath.addObserver { [weak self] snapshot in
            self?.handleNetworkPathChange(snapshot)
        }
        CaptchaController.shared.resetPushSuppression()
        let persistLogs = UserDefaults.standard.object(forKey: DefaultsKeys.persistLogs) as? Bool ?? false
        if !persistLogs {
            ErrorLogger.shared.clear()
        }
        startActiveTimers()
    }

    func stop() {
        ErrorLogger.shared.shipBatch()
        autoReconnectWork?.cancel()
        autoReconnectWork = nil
        backoffTickTimer?.invalidate()
        backoffTickTimer = nil
        retryBackoffSeconds = 0
        autoReconnectAttempt = 0
        everConnected = false
        inRetryCycle = false
        probeFailureStreak = 0
        lastRxTotalAtProbe = 0
        lastInterfaceIndex = 0
        if let id = networkPathObserverID {
            networkPath.removeObserver(id)
            networkPathObserverID = nil
        }
        networkPath.deactivate()
        CaptchaController.shared.resetPushSuppression()
        CaptchaController.shared.hide()
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [lostNotifID, recoveredNotifID])
        if ftunStarted {
            ftunStarted = false
            let ftun = self.ftun
            ftunQueue.async { ftun.stop() }
        }
        localTunnelUp = false
        localTunnelHandshakeAgeSec = 0
        remoteTunnelUp = false
        remoteTunnelHandshakeAgeSec = 0
        mobile.stop()
        mobile.setProtect(nil)
        protector.deactivate()
        audio.stop()
        isRunning = false
        state = .idle
        connectedStreams = 0
        totalStreams = 0
        errorMessage = ""
        stopTimers()
    }

    // MARK: – Запуск/рестарт Mobile

    // subUrl у нас всегда пустой, поэтому синхронный фетч подписки внутри
    // startLocked (см. mobile/api.go) для нас недостижим — гонять start на
    // фоновой очереди пока незачем. Понадобится, когда появится поддержка
    // subUrl.
    private func startMobile(_ cfg: FreeTurnConfig) throws {
        // Ставим protect до start: апстрим читает его в момент dial, поэтому на
        // уже открытые сокеты он не распространяется (план, фаза 5.1).
        protector.activate()
        mobile.setProtect(protector)
        try mobile.start(configJSON: CoreConfigBuilder.build(config: cfg.config, links: cfg.links).encodedJSON())
    }

    private func restartMobile(_ cfg: FreeTurnConfig) throws {
        try mobile.restart(configJSON: CoreConfigBuilder.build(config: cfg.config, links: cfg.links).encodedJSON())
    }

    // Вторая половина дороги (план, фаза 2): поднимается один раз за сессию,
    // после первого connected внешней половины — реконнект mobile её не
    // трогает, в этом весь смысл развязки. Не blocking: ошибка тут не должна
    // рушить уже поднятый внешний туннель, только логируется.
    private func startLocalTunnelIfNeeded() {
        guard !ftunStarted, let config, config.config.useLocalTunnel else { return }
        // Молчать тут нельзя: снаружи это выглядит как «туннель подключился,
        // а интернета нет» — весь трафик уходит в utun и умирает, потому что
        // локальную половину поднимать нечем.
        guard let local = localWGConfig.load() else {
            ErrorLogger.shared.appendAppLine(
                level: "ERR", message: "локальный туннель не поднят: нет локального конфига WG"
            )
            return
        }
        guard let external = externalWGConfig.load(for: config.config.id) else {
            ErrorLogger.shared.appendAppLine(
                level: "ERR", message: "локальный туннель не поднят: у профиля нет конфига VPN-сервера"
            )
            return
        }
        // Оба сокета сидят на loopback: совпали порты — responder не забиндится
        // («address already in use»), туннель встанет, а интернета не будет.
        // Ловим до старта, иначе диагноз приходится читать из логов ftun.
        let relay = relayAddr(for: config.config)
        if Validators.port(ofEndpoint: relay) == local.port {
            ErrorLogger.shared.appendAppLine(
                level: "ERR",
                message: "локальный туннель не поднят: порт \(local.port) занят туннелем (\(relay)) — задайте разные порты"
            )
            return
        }
        let bypass = bypassRoutes(config.config.splitTunnel)
        let req = FtunStartRequest(
            remoteConf: external.remoteConfText,
            localPrivateKey: local.serverPrivateKey,
            localPeerPublicKey: local.clientPublicKey,
            relayAddr: relay,
            listenPort: local.port,
            mtu: LocalConfigBuilder.mtu,
            bypassCIDRs: bypass,
            bypassExcludeCIDRs: BypassRoutes.excludes(address: external.address, dns: external.dns)
        )
        // Обходные сокеты netstack'а тоже обязаны выходить мимо VPN —
        // без protect обход замкнулся бы сам на себя (фаза 5.2).
        protector.activate()
        ftun.setProtect(protector)
        // Флаг ставим до ухода в очередь: он же защищает от второго старта,
        // пока первый ещё поднимается.
        ftunStarted = true
        ftunQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ftun.start(configJSON: req.encodedJSON())
                let mode = config.config.splitTunnel.enabled ? config.config.splitTunnel.mode.title.lowercased() : "стандартный"
                ErrorLogger.shared.appendAppLine(
                    level: "INF",
                    message: "локальный туннель поднят, режим «\(mode)», мимо туннеля: \(bypass.count) подсетей"
                )
                // Обновляем списки только теперь, когда дорога уже работает, и
                // только ради следующего запуска — на старте этот запрос утонул
                // бы в ещё не поднятом туннеле (см. BypassRoutes.swift:8-13).
                Task {
                    await BypassRoutes.refresh()
                    await SplitTunnelListFetcher.refreshStale(config.config.splitTunnel.sources)
                }
            } catch {
                ErrorLogger.shared.appendAppLine(
                    level: "ERR", message: "локальный туннель не поднялся: \(error.localizedDescription)"
                )
                DispatchQueue.main.async { self.ftunStarted = false }
            }
        }
    }

    // MARK: – Push от EventSinkBridge

    // Единственный источник TunnelState теперь — этот метод (вызывается из
    // EventSinkBridge.onState на main thread). Раньше то же самое читалось
    // поллингом getState() раз в 0.5с.
    func handleState(_ goState: String, streams: Int, total: Int, errMsg: String) {
        let st = TunnelState(goState: goState)
        state = st
        connectedStreams = streams
        totalStreams = total
        errorMessage = errMsg

        if st == .connected {
            everConnected = true
            autoReconnectAttempt = 0
            probeFailureStreak = 0
            CaptchaController.shared.resetPushSuppression()
            if inRetryCycle {
                inRetryCycle = false
                ErrorLogger.shared.appendAppLine(level: "INF", message: "туннель восстановлен")
                postRecoveredNotification()
            }
            startLocalTunnelIfNeeded()
        }

        // Пишем ошибку в единый буфер когда она появляется впервые.
        if !errMsg.isEmpty && errMsg != lastLoggedError {
            lastLoggedError = errMsg
            ErrorLogger.shared.appendAppLine(level: "ERR", message: errMsg)
        } else if errMsg.isEmpty {
            lastLoggedError = ""
        }

        let active = (st == .connecting || st == .connected || st == .captcha)
        // Туннель оборвался после успешного коннекта — в retry-цикл.
        if st == .error && everConnected {
            enterRetryCycle()
            return
        }
        isRunning = active
        if !active {
            if st == .error && !everConnected {
                // Так и не подключились — пуш с гардом видимости UI внутри
                // postInitialConnectFailureNotification.
                postInitialConnectFailureNotification()
            }
            ErrorLogger.shared.shipBatch()
            stopTimers()
            audio.stop()
        }
    }

    // MARK: – Унифицированный вход в retry-цикл

    // Единая точка входа для всех источников «связь с туннелем потеряна»:
    // ошибка из Go (connected→error), провал healthcheck-зонда. Смена сети —
    // отдельные входы (handleInterfaceChanged/leaveWaitingNetwork), они не
    // тратят бекофф. Гард на everConnected: до первого успешного коннекта
    // реконнект не делаем — там работает свой watchdog Go, и пуш
    // «Переподключаемся» был бы ложью.
    private func enterRetryCycle() {
        guard isRunning, config != nil, everConnected else { return }
        beginRetryCycleIfNeeded(reason: "потеряна связь")
        triggerAutoReconnect()
    }

    // Пуш и WRN-строка — только на границе эпизода (план, фаза 2.4: шум
    // внутри цикла — на DBG). Общий вход для всех трёх триггеров реконнекта.
    private func beginRetryCycleIfNeeded(reason: String) {
        guard !inRetryCycle else { return }
        inRetryCycle = true
        ErrorLogger.shared.appendAppLine(level: "WRN", message: "туннель прервался: \(reason)")
        postReconnectingNotification()
    }

    // MARK: – Смена сети (план, фаза 2.1/2.2)

    // Единственный монитор пути на приложение (NetworkPath) — колбэк
    // приходит на main (см. NetworkPath.handle). isRunning гард: наблюдатель
    // снимается в stop(), но путь мог обновиться в узком окне между
    // событиями до отписки.
    private func handleNetworkPathChange(_ snapshot: NetworkPathSnapshot) {
        guard isRunning else { return }
        let previousIndex = lastInterfaceIndex
        lastInterfaceIndex = snapshot.interfaceIndex

        if !snapshot.isSatisfied {
            enterWaitingNetwork()
            return
        }
        if state == .waitingNetwork {
            leaveWaitingNetwork()
            return
        }
        // Оба индекса ненулевые и различаются — сокеты ядра (IP_BOUND_IF)
        // привязаны к интерфейсу, которого больше нет, и мертвы навсегда
        // (план, «Разбор», причина 2). appearance из 0 — это первый снимок
        // после activate(), а не смена, её не считаем.
        if previousIndex != 0, snapshot.interfaceIndex != 0, previousIndex != snapshot.interfaceIndex {
            handleInterfaceChanged()
        }
    }

    // Путь unsatisfied во время активной сессии: не жжём попытки реконнекта
    // на отсутствие сети как таковое — ждём его появления молча.
    private func enterWaitingNetwork() {
        guard isRunning, config != nil, everConnected, state != .waitingNetwork else { return }
        autoReconnectWork?.cancel()
        autoReconnectWork = nil
        backoffTickTimer?.invalidate()
        backoffTickTimer = nil
        retryBackoffSeconds = 0
        state = .waitingNetwork
        connectedStreams = 0
        ErrorLogger.shared.appendAppLine(level: "DBG", message: "путь сети недоступен, ждём восстановления")
    }

    // Путь снова satisfied после waitingNetwork — реконнект сразу, без
    // бекоффа: обрыв уже случился раньше, ждать тут нечего.
    private func leaveWaitingNetwork() {
        guard isRunning, config != nil, everConnected else { return }
        ErrorLogger.shared.appendAppLine(level: "DBG", message: "путь сети восстановлен")
        beginRetryCycleIfNeeded(reason: "путь сети восстановлен")
        triggerAutoReconnect(immediate: true)
    }

    // Физический интерфейс сменился под живой сессией — сокеты ядра мертвы
    // навсегда (IP_BOUND_IF на старый индекс), ждать зонда ~5с незачем.
    // Ступени 0–1 тут не помогут (они не трогают protect-привязку сокетов),
    // поэтому сразу поднимаем пол лестницы до restartMobile.
    private func handleInterfaceChanged() {
        guard isRunning, config != nil, everConnected else { return }
        ErrorLogger.shared.appendAppLine(level: "DBG", message: "сменился физический интерфейс сети")
        autoReconnectAttempt = max(autoReconnectAttempt, 2)
        beginRetryCycleIfNeeded(reason: "сменился физический интерфейс сети")
        triggerAutoReconnect(immediate: true)
    }

    // MARK: – Авто-переподключение при обрыве туннеля

    // 1, 2, 4, 8, 15, 15, …
    private func autoReconnectDelay(forAttempt attempt: Int) -> TimeInterval {
        let capped = min(attempt, 4)
        let v = Foundation.pow(2.0, Double(capped))
        return min(v, 15.0)
    }

    // Никогда не сдаётся (план, фаза 2.4) — бекофф упирается в потолок 15с и
    // продолжается, пока сессия жива. immediate=true пропускает ожидание
    // (смена сети — обрыв уже случился, ждать нечего).
    private func triggerAutoReconnect(immediate: Bool = false) {
        guard isRunning, config != nil else { return }
        guard networkPath.currentSnapshot.isSatisfied else {
            enterWaitingNetwork()
            return
        }
        connectedStreams = 0
        let stepAttempt = autoReconnectAttempt
        autoReconnectAttempt = stepAttempt + 1
        let step = recoveryStep(forAttempt: stepAttempt)

        if immediate {
            backoffTickTimer?.invalidate()
            backoffTickTimer = nil
            retryBackoffSeconds = 0
            autoReconnectWork?.cancel()
            autoReconnectWork = nil
            performRecoveryStep(step)
            return
        }

        state = .retryBackoff
        let delay = autoReconnectDelay(forAttempt: stepAttempt)
        ErrorLogger.shared.appendAppLine(
            level: "DBG",
            message: "соединение прервано, переподключение через \(Int(delay))с (ступень \(step.rawValue))"
        )
        retryBackoffSeconds = Int(delay)
        startBackoffTick()
        autoReconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performRecoveryStep(step) }
        autoReconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startBackoffTick() {
        backoffTickTimer?.invalidate()
        backoffTickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.retryBackoffSeconds > 0 { self.retryBackoffSeconds -= 1 }
        }
    }

    // Ступень 3 требует полного перезапуска ftun-очереди, ступени 2–3 идут
    // через restartMobile — Go сам пришлёт onState и подтвердит успех.
    // Ступени 0–1 ничего не пересоздают, поэтому подтверждаем их отдельно
    // (confirmCheapStepOutcome) — Go может неделями не прислать новый push,
    // если сам считает себя в порядке, а сломана только наша сторона.
    private func performRecoveryStep(_ step: RecoveryStep) {
        guard isRunning, let config else { return }
        backoffTickTimer?.invalidate()
        backoffTickTimer = nil
        retryBackoffSeconds = 0

        switch step {
        case .nudge:
            guard ftunStarted else {
                // Без WG-in-WG nudge'ить нечего — сразу пробуем wake.
                performRecoveryStep(.wake)
                return
            }
            state = .connecting
            ErrorLogger.shared.appendAppLine(level: "DBG", message: "ступень 0: nudge WG-in-WG")
            let ftun = self.ftun
            ftunQueue.async { ftun.nudge() }
            scheduleCheapStepFollowUp()
        case .wake:
            state = .connecting
            ErrorLogger.shared.appendAppLine(level: "DBG", message: "ступень 1: mobile.wake()")
            mobile.wake()
            scheduleCheapStepFollowUp()
        case .restart:
            state = .connecting
            ErrorLogger.shared.appendAppLine(level: "DBG", message: "ступень 2: restartMobile")
            do {
                try restartMobile(config)
            } catch {
                triggerAutoReconnect()
            }
        case .fullRestart:
            state = .connecting
            ErrorLogger.shared.appendAppLine(level: "DBG", message: "ступень 3: полный перезапуск ftun + restartMobile")
            if ftunStarted {
                ftunStarted = false
                let ftun = self.ftun
                ftunQueue.async { [weak self] in
                    ftun.stop()
                    DispatchQueue.main.async { self?.startLocalTunnelIfNeeded() }
                }
            }
            do {
                try restartMobile(config)
            } catch {
                triggerAutoReconnect()
            }
        }
    }

    private static let cheapStepFollowUpDelay: TimeInterval = 3

    // Ступени 0–1 не трогают Go-сессию — Go может и не прислать новый push,
    // если сам считает себя в порядке. Перепроверяем зондом сами и либо
    // тихо закрываем эпизод, либо эскалируем на следующую ступень.
    private func scheduleCheapStepFollowUp() {
        let work = DispatchWorkItem { [weak self] in self?.confirmCheapStepOutcome() }
        autoReconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cheapStepFollowUpDelay, execute: work)
    }

    private func confirmCheapStepOutcome() {
        guard isRunning, inRetryCycle else { return }
        reachabilityProbe { [weak self] ok in
            guard let self, self.isRunning, self.inRetryCycle else { return }
            if ok {
                self.recoverSilently()
            } else {
                self.triggerAutoReconnect()
            }
        }
    }

    // Ступени 0–1 не дают Go повода прислать connected сам — подтверждаем
    // восстановление локально и закрываем эпизод тем же путём, что и
    // handleState(connected): сброс попыток, снятие пуша «Переподключаемся».
    private func recoverSilently() {
        inRetryCycle = false
        autoReconnectAttempt = 0
        probeFailureStreak = 0
        state = .connected
        ErrorLogger.shared.appendAppLine(level: "INF", message: "туннель восстановлен без пересоздания сессии")
        postRecoveredNotification()
    }

    // Пуши шлём только когда пользователь не смотрит вкладку «Туннель» в
    // активном приложении — иначе UI и так показывает статус.
    private func shouldPostStatusPush() -> Bool {
        if UIApplication.shared.applicationState != .active { return true }
        return UIState.currentTab != UIState.tunnelTabTag
    }

    // Пуш при входе в retry-цикл из connected. Текст нейтральный (без слова
    // «ошибка») потому что снаружи это выглядит как восстановимая пауза, а не
    // фейл — туннель сам поднимется. Отдельная функция от
    // postInitialConnectFailureNotification, чтобы тексты не путались.
    private func postReconnectingNotification() {
        guard shouldPostStatusPush() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Переподключаемся"
        content.body = "Восстанавливаем туннель"
        content.sound = .default
        let req = UNNotificationRequest(identifier: lostNotifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Пуш на путь idle→connecting→error (ни разу не подключились). Здесь слово
    // «ошибка» уместно: пользователь явно жал «Подключиться» и оно не удалось.
    private func postInitialConnectFailureNotification() {
        guard shouldPostStatusPush() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ошибка подключения"
        content.body = "Вернитесь в приложение чтобы попробовать подключиться повторно"
        content.sound = .default
        let req = UNNotificationRequest(identifier: lostNotifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func postRecoveredNotification() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [lostNotifID])
        guard shouldPostStatusPush() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Переподключились"
        content.body = "Туннель снова доступен"
        content.sound = .default
        let req = UNNotificationRequest(identifier: recoveredNotifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: – Статистика трафика (лёгкий поллинг)

    private func startActiveTimers() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snap = self.mobile.getState()
            DispatchQueue.main.async {
                self.txTotalBytes = snap?.txTotal ?? 0
                self.rxTotalBytes = snap?.rxTotal ?? 0
                self.txRateBytesPerSec = snap?.txRate ?? 0
                self.rxRateBytesPerSec = snap?.rxRate ?? 0
            }
            // Пропускаем тик, если предыдущий опрос ещё не вернулся: stats
            // берёт тот же мьютекс, что start/stop, и на медленном ответе
            // тики копились бы в очереди.
            guard self.ftunStarted, !self.ftunStatsInFlight else { return }
            self.ftunStatsInFlight = true
            self.ftunQueue.async {
                let ftunSnap = self.ftun.stats()
                DispatchQueue.main.async {
                    self.ftunStatsInFlight = false
                    self.localTunnelUp = ftunSnap?.localUp ?? false
                    self.localTunnelHandshakeAgeSec = ftunSnap?.localHandshakeAgeSec ?? 0
                    self.remoteTunnelUp = ftunSnap?.remoteUp ?? false
                    self.remoteTunnelHandshakeAgeSec = ftunSnap?.remoteHandshakeAgeSec ?? 0
                }
            }
        }
        logShipTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            ErrorLogger.shared.shipBatch()
        }
        startProbing()
    }

    private func stopTimers() {
        statsTimer?.invalidate(); statsTimer = nil
        logShipTimer?.invalidate(); logShipTimer = nil
        probeTimer?.invalidate(); probeTimer = nil
        lastLoggedError = ""
    }

    // MARK: – Зонд туннеля

    private func startProbing() {
        probeTimer?.invalidate()
        probeTimer = Timer.scheduledTimer(withTimeInterval: Self.probeInterval, repeats: true) { [weak self] _ in
            self?.performProbe()
        }
    }

    private func performProbe() {
        guard state == .connected, isRunning else { return }
        // Отсутствие сети как таковое — не поломка туннеля, это отдельный
        // путь через enterWaitingNetwork (handleNetworkPathChange); зонд тут
        // ничего нового не скажет и только потратил бы попытку.
        guard networkPath.currentSnapshot.isSatisfied else { return }
        if probeSkippable() {
            probeFailureStreak = 0
            return
        }
        reachabilityProbe { [weak self] ok in
            guard let self, self.state == .connected, self.isRunning else { return }
            if ok {
                self.probeFailureStreak = 0
                return
            }
            self.probeFailureStreak += 1
            ErrorLogger.shared.appendAppLine(level: "DBG",
                message: "tunnel probe failed (\(self.probeFailureStreak)/2)")
            // Один провал на плохом LTE — норма (таймаут ~4.5с). Реагируем
            // только на два подряд.
            if self.probeFailureStreak >= 2 {
                self.probeFailureStreak = 0
                self.enterRetryCycle()
            }
        }
    }

    // Дешёвые локальные индикаторы уже говорят «живо» — растёт rxTotal ядра,
    // и (если WG-in-WG поднят) внешняя половина ftun отвечала на хендшейк
    // недавно. Экономим сетевой запрос там, где и так видно, что туннель жив.
    private func probeSkippable() -> Bool {
        let rxGrowing = rxTotalBytes > lastRxTotalAtProbe
        lastRxTotalAtProbe = rxTotalBytes
        guard rxGrowing else { return false }
        guard ftunStarted else { return true }
        return remoteTunnelUp && remoteTunnelHandshakeAgeSec < Int64(Self.probeInterval * 3)
    }
}

enum AppError: LocalizedError {
    case noConfig
    var errorDescription: String? { "Конфиг не загружен" }
}
