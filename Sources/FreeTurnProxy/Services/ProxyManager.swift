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

    private var config: FreeTurnConfig?
    private var statsTimer: Timer?
    private var logShipTimer: Timer?   // ship unified buffer → worker (10s)
    private var probeTimer: Timer?     // зонд живости туннеля (5s)
    private var lastLoggedError = ""
    private let audio = AudioKeepAlive()
    private let mobile: MobileAPI
    private let ftun: FtunAPI
    private let localTunnelProfiles: LocalTunnelProfileStoring

    private static let probeInterval: TimeInterval = 5
    private static let probeURL = URL(string: "http://captive.apple.com")!

    // WG-in-WG (план, фаза 2): локальный responder слушает 127.0.0.1:9000,
    // апстрим-релей переезжает на 127.0.0.1:9001 (см. SavedConfig.listen,
    // должен быть выставлен на этот адрес при сборке конфига с
    // useLocalTunnel). ftun поднимается один раз за сессию — после первого
    // connected — и не трогается реконнектом внешней половины.
    private static let localResponderPort = 9000
    private static let relayAddrForLocalTunnel = "127.0.0.1:9001"
    private var ftunStarted = false

    // Реконнект-цикл стартует из двух мест, оба идут через enterRetryCycle():
    //   • Go выдал error из connected (push через EventSink.onState);
    //   • healthcheck-зонд (captive.apple.com) провалился.
    // Сам реконнект — один MobileRestart, без промежуточного stop+start:
    // ядро атомарно подменяет текущую сессию, поэтому нет окна, в котором
    // push мог бы прислать «случайный» idle.
    //
    // Третьим триггером была смена сети (NetworkMonitor) — убран. Включение
    // самого AmneziaWG тоже выглядит как смена пути, поэтому реконнект бил по
    // рукам ровно в тот момент, когда всё только поднималось. Реальный обрыв
    // при переходе LTE↔Wi-Fi никуда не делся, но ловится зондом за ~5с — по
    // факту поломки, а не по событию, которое поломкой быть не обязано.
    private let protector = SocketProtector.shared

    // Инжектируем, чтобы тесты не зависели от содержимого UserDefaults.
    // Синхронный намеренно: сеть на пути старта локальной половины даёт
    // дедлок (см. startLocalTunnelIfNeeded).
    private let bypassRoutes: () -> [String]

    // Срабатывает только если в течение сессии хотя бы раз дошли до connected —
    // connecting→error не ретраит (это первичный провал коннекта, не реконнект).
    private var everConnected = false
    private var autoReconnectAttempt = 0
    private var autoReconnectWork: DispatchWorkItem?
    private var backoffTickTimer: Timer?
    // Стартует на первом входе в retry-цикл из connected, гасится:
    //   • на успешном переподключении (там же шлём «Переподключились»);
    //   • на stop()/start();
    //   • когда сами сдались (если когда-нибудь добавим limit).
    private var inRetryCycle = false
    private let lostNotifID = "tunnel-lost"
    private let recoveredNotifID = "tunnel-recovered"
    private let gaveUpNotifID = "tunnel-gave-up"
    private static let maxAutoReconnectAttempts = 5

    // Сколько секунд осталось до следующей попытки реконнекта. Обновляется раз
    // в секунду, чтобы UI мог показывать «Переподключаемся через X с».
    @Published var retryBackoffSeconds: Int = 0

    var serverAddress: String { config?.config.peer ?? "" }

    private init() {
        self.mobile = LiveMobileAPI()
        self.ftun = LiveFtunAPI()
        self.localTunnelProfiles = KeychainLocalTunnelProfileStore()
        self.bypassRoutes = { BypassRoutes.current() }
    }

    // Инжектируемый init — для тестов с MockMobileAPI/MockFtunAPI.
    init(mobile: MobileAPI, ftun: FtunAPI = LiveFtunAPI(),
         localTunnelProfiles: LocalTunnelProfileStoring = KeychainLocalTunnelProfileStore(),
         bypassRoutes: @escaping () -> [String] = { [] }) {
        self.mobile = mobile
        self.ftun = ftun
        self.localTunnelProfiles = localTunnelProfiles
        self.bypassRoutes = bypassRoutes
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
        CaptchaController.shared.resetPushSuppression()
        CaptchaController.shared.hide()
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [lostNotifID, recoveredNotifID])
        if ftunStarted {
            ftun.stop()
            ftunStarted = false
        }
        localTunnelUp = false
        localTunnelHandshakeAgeSec = 0
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
        guard !ftunStarted, let config, config.config.useLocalTunnel,
              let profileID = config.config.wgProfileID,
              let profile = localTunnelProfiles.load(profileID) else { return }
        let bypass = bypassRoutes()
        do {
            let req = FtunStartRequest(
                remoteConf: profile.remoteConfText,
                localPrivateKey: profile.serverPrivateKey,
                localPeerPublicKey: profile.clientPublicKey,
                relayAddr: Self.relayAddrForLocalTunnel,
                listenPort: Self.localResponderPort,
                mtu: LocalConfigBuilder.mtu,
                bypassCIDRs: bypass,
                bypassExcludeCIDRs: BypassRoutes.excludes(address: profile.address)
            )
            // Обходные сокеты netstack'а тоже обязаны выходить мимо VPN —
            // без protect обход замкнулся бы сам на себя (фаза 5.2).
            protector.activate()
            ftun.setProtect(protector)
            try ftun.start(configJSON: req.encodedJSON())
            ftunStarted = true
            ErrorLogger.shared.appendAppLine(
                level: "INF", message: "локальный туннель поднят, мимо туннеля: \(bypass.count) подсетей"
            )
            // Список подсетей VK обновляем только теперь, когда дорога уже
            // работает, и только ради следующего запуска — на старте этот
            // запрос утонул бы в ещё не поднятом туннеле.
            Task { await BypassRoutes.refresh() }
        } catch {
            ErrorLogger.shared.appendAppLine(
                level: "ERR", message: "локальный туннель не поднялся: \(error.localizedDescription)"
            )
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
            CaptchaController.shared.resetPushSuppression()
            if inRetryCycle {
                inRetryCycle = false
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
    // ошибка из Go (connected→error), провал healthcheck-зонда, смена сети.
    // Гард на everConnected: до первого успешного коннекта реконнект не делаем —
    // там работает свой 15с-watchdog Go, и пуш «Переподключаемся» был бы ложью.
    private func enterRetryCycle() {
        guard isRunning, config != nil, everConnected else { return }
        if !inRetryCycle {
            inRetryCycle = true
            postReconnectingNotification()
        }
        triggerAutoReconnect()
    }

    // MARK: – Авто-переподключение при обрыве туннеля

    // 1, 2, 4, 8, 15, 15, …
    private func autoReconnectDelay() -> TimeInterval {
        let capped = min(autoReconnectAttempt, 4)
        let v = Foundation.pow(2.0, Double(capped))
        return min(v, 15.0)
    }

    private func triggerAutoReconnect() {
        guard isRunning, config != nil else { return }
        if autoReconnectAttempt >= Self.maxAutoReconnectAttempts {
            giveUpReconnecting()
            return
        }
        state = .retryBackoff
        connectedStreams = 0
        let delay = autoReconnectDelay()
        let n = autoReconnectAttempt + 1
        ErrorLogger.shared.appendAppLine(
            level: "WRN",
            message: "соединение прервано, переподключение через \(Int(delay))с (попытка \(n))"
        )
        autoReconnectAttempt = n
        retryBackoffSeconds = Int(delay)
        startBackoffTick()
        autoReconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performAutoReconnect() }
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

    private func performAutoReconnect() {
        guard isRunning, let config else { return }
        backoffTickTimer?.invalidate()
        backoffTickTimer = nil
        retryBackoffSeconds = 0
        state = .connecting
        do {
            try restartMobile(config)
        } catch {
            // Рестарт сам бросил исключение — считаем как очередной фейл и
            // ждём следующий бекофф.
            triggerAutoReconnect()
        }
    }

    // Бюджет попыток исчерпан — гасим туннель вместо бесконечного бекоффа.
    private func giveUpReconnecting() {
        ErrorLogger.shared.appendAppLine(
            level: "ERR",
            message: "переподключение не удалось после \(Self.maxAutoReconnectAttempts) попыток, останавливаемся"
        )
        stop()
        state = .error
        errorMessage = "Не удалось переподключиться после \(Self.maxAutoReconnectAttempts) попыток"
        postGaveUpNotification()
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

    private func postGaveUpNotification() {
        guard shouldPostStatusPush() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Подключение разорвано"
        content.body = "Не удалось переподключиться после \(Self.maxAutoReconnectAttempts) попыток"
        content.sound = .default
        let req = UNNotificationRequest(identifier: gaveUpNotifID, content: content, trigger: nil)
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
            guard self.ftunStarted else { return }
            let ftunSnap = self.ftun.stats()
            DispatchQueue.main.async {
                self.localTunnelUp = ftunSnap?.localUp ?? false
                self.localTunnelHandshakeAgeSec = ftunSnap?.localHandshakeAgeSec ?? 0
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
        var req = URLRequest(url: Self.probeURL)
        req.timeoutInterval = Self.probeInterval - 0.5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, error in
            DispatchQueue.main.async {
                guard let self, self.state == .connected, self.isRunning else { return }
                if let error {
                    ErrorLogger.shared.appendAppLine(level: "WRN",
                        message: "tunnel probe failed: \(error.localizedDescription)")
                    self.enterRetryCycle()
                }
            }
        }.resume()
    }
}

enum AppError: LocalizedError {
    case noConfig
    var errorDescription: String? { "Конфиг не загружен" }
}
