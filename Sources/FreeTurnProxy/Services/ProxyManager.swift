import Foundation
import Mobile

final class ProxyManager: ObservableObject {
    static let shared = ProxyManager()

    @Published var isRunning = false
    @Published var state: String = "idle"
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

    private static let probeInterval: TimeInterval = 5
    private static let probeURL = URL(string: "http://captive.apple.com")!

    // Переподключение при смене сети (LTE↔Wi-Fi). isReconnecting замораживает
    // поллинг, чтобы промежуточный idle между Stop и Start не уронил туннель.
    private let network = NetworkMonitor()
    private var reconnectWork: DispatchWorkItem?
    private var isReconnecting = false

    var serverAddress: String { config?.peer ?? "" }

    private init() {}

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
        MobileSetManualCaptcha(config.manualCaptcha)
        var startError: NSError?
        MobileStart(config.link, config.peer, config.dns ?? "", config.listen ?? "127.0.0.1:9000", config.transport, config.obfKey, "ios", &startError)
        if let startError { throw startError }
        isRunning = true
        let persistLogs = UserDefaults.standard.object(forKey: "persist_logs") as? Bool ?? false
        if persistLogs {
            ErrorLogger.shared.resetGoPosition()
        } else {
            ErrorLogger.shared.clear()
        }
        startPolling()
        startLogTimers()
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
        isReconnecting = false
        MobileStop()
        audio.stop()
        isRunning = false
        state = "idle"
        connectedStreams = 0
        totalStreams = 0
        errorMessage = ""
        stopPolling()
    }

    // MARK: – Переподключение при смене сети

    private func scheduleReconnect() {
        guard isRunning, config != nil else { return }
        reconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performReconnect() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func performReconnect(retry: Int = 1) {
        guard isRunning, let config else { return }
        isReconnecting = true
        state = "connecting"
        connectedStreams = 0
        MobileStop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.isRunning, let config = self.config else { return }
            MobileSetManualCaptcha(config.manualCaptcha)
            var err: NSError?
            MobileStart(config.link, config.peer, config.dns ?? "", config.listen ?? "127.0.0.1:9000", config.transport, config.obfKey, "ios", &err)
            if err != nil, retry > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.performReconnect(retry: retry - 1)
                }
                return
            }
            if let err { self.errorMessage = err.localizedDescription }
            self.isReconnecting = false
        }
    }

    // MARK: – Polling

    private func startPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snap = MobileGetState()
            DispatchQueue.main.async {
                if self.isReconnecting { return }
                let st = snap?.state ?? "idle"
                self.state = st
                self.connectedStreams = snap?.streams ?? 0
                self.totalStreams = snap?.total ?? 0
                self.errorMessage = snap?.errMsg ?? ""
                self.txTotalBytes = snap?.txTotal ?? 0
                self.rxTotalBytes = snap?.rxTotal ?? 0
                self.txRateBytesPerSec = snap?.txRate ?? 0
                self.rxRateBytesPerSec = snap?.rxRate ?? 0

                // Пишем ошибку в единый буфер когда она появляется впервые.
                let err = snap?.errMsg ?? ""
                if !err.isEmpty && err != self.lastLoggedError {
                    self.lastLoggedError = err
                    ErrorLogger.shared.appendAppLine(level: "ERR", message: err)
                } else if err.isEmpty {
                    self.lastLoggedError = ""
                }

                let active = (st == "connecting" || st == "connected" || st == "captcha")
                self.isRunning = active
                if !active {
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
        guard state == "connected", isRunning, !isReconnecting else { return }
        var req = URLRequest(url: Self.probeURL)
        req.timeoutInterval = Self.probeInterval - 0.5
        URLSession.shared.dataTask(with: req) { [weak self] _, _, error in
            DispatchQueue.main.async {
                guard let self, self.state == "connected", self.isRunning else { return }
                if let error {
                    ErrorLogger.shared.appendAppLine(level: "WRN",
                        message: "tunnel probe failed: \(error.localizedDescription)")
                    self.scheduleReconnect()
                }
            }
        }.resume()
    }

    private func startLogTimers() {
        logPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            ErrorLogger.shared.ingestGoLogs(MobileGetLogs())
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
