import Foundation
import Mobile
import UserNotifications

final class ProxyManager: ObservableObject {
    static let shared = ProxyManager()

    @Published var isRunning = false
    @Published var state: TunnelState = .idle
    @Published var connectedStreams: Int = 0
    @Published var totalStreams: Int = 0
    @Published var errorMessage: String = ""
    @Published var configFileName: String?

    // Статистика трафика
    @Published var txTotalBytes: Int64 = 0
    @Published var rxTotalBytes: Int64 = 0
    @Published var txRateBytesPerSec: Int64 = 0
    @Published var rxRateBytesPerSec: Int64 = 0

    private var config: FreeTurnConfig?
    private var statusTimer: Timer?
    private var logPollTimer: Timer?   // ingestion Go → unified buffer (0.5s)
    private var logShipTimer: Timer?   // ship unified buffer → worker (10s)
    private var probeTimer: Timer?     // зонд живости туннеля (5s)
    private var lastLoggedError = ""
    private let audio = AudioKeepAlive()
    private let mobile: MobileAPI

    private static let probeInterval: TimeInterval = 5
    private static let probeURL = URL(string: "http://captive.apple.com")!

    // Переподключение при смене сети (LTE↔Wi-Fi). isReconnecting замораживает
    // поллинг, чтобы промежуточный idle между Stop и Start не уронил туннель.
    private let network = NetworkMonitor()
    private var reconnectWork: DispatchWorkItem?
    private var isReconnecting = false

    // Авто-переподключение при обрыве уже установленного туннеля
    // (connected → error). Срабатывает только если в течение сессии хотя бы раз
    // дошли до connected — connecting→error не ретраит.
    private var everConnected = false
    private var autoReconnectAttempt = 0
    private var autoReconnectWork: DispatchWorkItem?
    private var lostNotificationPosted = false
    private let lostNotifID = "tunnel-lost"

    var serverAddress: String { config?.peer ?? "" }

    private init() {
        self.mobile = LiveMobileAPI()
    }

    // Инжектируемый init — для тестов с MockMobileAPI.
    init(mobile: MobileAPI) {
        self.mobile = mobile
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
        lostNotificationPosted = false
        let persistLogs = UserDefaults.standard.object(forKey: DefaultsKeys.persistLogs) as? Bool ?? false
        if persistLogs {
            ErrorLogger.shared.resetGoPosition()
        } else {
            ErrorLogger.shared.clear()
        }
        startPolling()
        startActiveTimers()
        network.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleReconnect() }
        }
        network.start()
    }

    func stop() {
        ErrorLogger.shared.shipBatch()
        network.stop()
        reconnectWork?.cancel()
        reconnectWork = nil
        autoReconnectWork?.cancel()
        autoReconnectWork = nil
        autoReconnectAttempt = 0
        everConnected = false
        isReconnecting = false
        lostNotificationPosted = false
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [lostNotifID])
        mobile.stop()
        audio.stop()
        isRunning = false
        state = .idle
        connectedStreams = 0
        totalStreams = 0
        errorMessage = ""
        stopPolling()
    }

    // MARK: – Запуск Mobile (вынесено для повторного использования при reconnect)

    private func startMobile(_ cfg: FreeTurnConfig) throws {
        mobile.setManualCaptcha(cfg.manualCaptcha)
        try mobile.start(
            link: cfg.link,
            peer: cfg.peer,
            dns: cfg.dns ?? "",
            listen: cfg.listen ?? "127.0.0.1:9000",
            transport: cfg.transport,
            obfKey: cfg.obfKey,
            clientType: "ios"
        )
    }

    // MARK: – Переподключение при смене сети

    private func scheduleReconnect() {
        guard isRunning, config != nil else { return }
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performReconnect() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: – Авто-переподключение при обрыве туннеля

    static func isAutoReconnectEnabled() -> Bool {
        UserDefaults.standard.object(forKey: DefaultsKeys.autoReconnect) as? Bool ?? true
    }

    // 1, 2, 4, 8, 15, 15, …
    private func autoReconnectDelay() -> TimeInterval {
        let capped = min(autoReconnectAttempt, 4)
        let v = Foundation.pow(2.0, Double(capped))
        return min(v, 15.0)
    }

    private func triggerAutoReconnect() {
        guard isRunning, config != nil else { return }
        isReconnecting = true
        state = .connecting
        connectedStreams = 0
        let delay = autoReconnectDelay()
        let n = autoReconnectAttempt + 1
        ErrorLogger.shared.appendAppLine(
            level: "WRN",
            message: "соединение прервано, переподключение через \(Int(delay))с (попытка \(n))"
        )
        autoReconnectAttempt = n
        autoReconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performAutoReconnect() }
        autoReconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performAutoReconnect() {
        guard isRunning, config != nil else { return }
        mobile.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.isRunning, let config = self.config else { return }
            do {
                try self.startMobile(config)
                self.isReconnecting = false
            } catch {
                // Старт сам бросил исключение — считаем как очередной фейл и
                // ждём следующий бекофф (если автореконнект всё ещё включён).
                self.isReconnecting = false
                if Self.isAutoReconnectEnabled() {
                    self.triggerAutoReconnect()
                } else {
                    self.errorMessage = error.localizedDescription
                    self.state = .error
                    self.isRunning = false
                    self.stopPolling()
                    self.audio.stop()
                }
            }
        }
    }

    private func notifyConnectionLost() {
        guard !lostNotificationPosted else { return }
        lostNotificationPosted = true
        let content = UNMutableNotificationContent()
        content.title = "Подключение прервано"
        content.body = Self.isAutoReconnectEnabled()
            ? "Туннель оборвался, переподключаюсь автоматически."
            : "Туннель оборвался. Откройте приложение, чтобы переподключиться."
        content.sound = .default
        let req = UNNotificationRequest(identifier: lostNotifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func performReconnect(retry: Int = 1) {
        guard isRunning, config != nil else { return }
        isReconnecting = true
        state = .connecting
        connectedStreams = 0
        mobile.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.isRunning, let config = self.config else { return }
            do {
                try self.startMobile(config)
                self.isReconnecting = false
            } catch {
                if retry > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.performReconnect(retry: retry - 1)
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                    self.isReconnecting = false
                }
            }
        }
    }

    // MARK: – Polling

    private func startPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snap = self.mobile.getState()
            DispatchQueue.main.async {
                if self.isReconnecting { return }
                let st = TunnelState(goState: snap?.state ?? "idle")
                self.state = st
                self.connectedStreams = snap?.streams ?? 0
                self.totalStreams = snap?.total ?? 0
                self.errorMessage = snap?.errMsg ?? ""
                self.txTotalBytes = snap?.txTotal ?? 0
                self.rxTotalBytes = snap?.rxTotal ?? 0
                self.txRateBytesPerSec = snap?.txRate ?? 0
                self.rxRateBytesPerSec = snap?.rxRate ?? 0

                if st == .connected {
                    self.everConnected = true
                    self.autoReconnectAttempt = 0
                    self.lostNotificationPosted = false
                }

                // Пишем ошибку в единый буфер когда она появляется впервые.
                let err = snap?.errMsg ?? ""
                if !err.isEmpty && err != self.lastLoggedError {
                    self.lastLoggedError = err
                    ErrorLogger.shared.appendAppLine(level: "ERR", message: err)
                } else if err.isEmpty {
                    self.lastLoggedError = ""
                }

                let active = (st == .connecting || st == .connected || st == .captcha)
                // Авто-переподключение: туннель оборвался после успешного коннекта
                // и пользователь не отключал тоггл «переподключаться при сбое».
                let shouldAutoReconnect = (st == .error && self.everConnected && Self.isAutoReconnectEnabled())
                if shouldAutoReconnect {
                    self.notifyConnectionLost()
                    self.triggerAutoReconnect()
                    return
                }
                self.isRunning = active
                if !active {
                    if st == .error && self.everConnected {
                        // Авто-реконнект выключен — уведомление всё равно полезно.
                        self.notifyConnectionLost()
                    }
                    ErrorLogger.shared.shipBatch()
                    self.stopPolling()
                    self.audio.stop()
                }
            }
        }
    }

    private func stopPolling() {
        statusTimer?.invalidate(); statusTimer = nil
        logPollTimer?.invalidate(); logPollTimer = nil
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
        guard state == .connected, isRunning, !isReconnecting else { return }
        var req = URLRequest(url: Self.probeURL)
        req.timeoutInterval = Self.probeInterval - 0.5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, error in
            DispatchQueue.main.async {
                guard let self, self.state == .connected, self.isRunning else { return }
                if let error {
                    ErrorLogger.shared.appendAppLine(level: "WRN",
                        message: "tunnel probe failed: \(error.localizedDescription)")
                    self.scheduleReconnect()
                }
            }
        }.resume()
    }

    private func startActiveTimers() {
        logPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            ErrorLogger.shared.ingestGoLogs(self.mobile.getLogs())
        }
        logShipTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            ErrorLogger.shared.shipBatch()
        }
        startProbing()
    }
}

enum AppError: LocalizedError {
    case noConfig
    var errorDescription: String? { "Конфиг не загружен" }
}
