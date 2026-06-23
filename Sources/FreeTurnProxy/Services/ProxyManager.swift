import Foundation
import Ios

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
    private let audio = AudioKeepAlive()

    // Переподключение при смене сети (LTE↔Wi-Fi). isReconnecting замораживает
    // поллинг, чтобы промежуточный idle между Stop и Start не уронил туннель.
    private let network = NetworkMonitor()
    private var reconnectWork: DispatchWorkItem?
    private var isReconnecting = false

    // Адрес сервера загруженного конфига — показываем на экране подключения.
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
        IosSetManualCaptcha(config.manualCaptcha)
        var startError: NSError?
        IosStart(config.link, config.peer, config.dns ?? "", config.listen ?? "127.0.0.1:9000", config.transport, config.obfKey, &startError)
        if let startError { throw startError }
        isRunning = true
        startPolling()
        network.onChange = { [weak self] in
            DispatchQueue.main.async { self?.scheduleReconnect() }
        }
        network.start()
    }

    func stop() {
        network.stop()
        reconnectWork?.cancel()
        reconnectWork = nil
        isReconnecting = false
        IosStop()
        audio.stop()
        isRunning = false
        state = "idle"
        connectedStreams = 0
        totalStreams = 0
        errorMessage = ""
        stopPolling()
    }

    // MARK: – Переподключение при смене сети

    // Дебаунс: NWPathMonitor может дёрнуть несколько раз подряд во время свитча.
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
        IosStop()
        // Дать старой сессии освободить локальный listener. UDP-loopback без
        // TIME_WAIT, поэтому хватает короткой паузы перед повторным bind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.isRunning, let config = self.config else { return }
            IosSetManualCaptcha(config.manualCaptcha)
            var err: NSError?
            IosStart(config.link, config.peer, config.dns ?? "", config.listen ?? "127.0.0.1:9000", config.transport, config.obfKey, &err)
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

    private func startPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Единый консистентный срез: стадия подключения + статистика в одном
            // вызове. isRunning выводим из state, отдельного флага в Go больше нет.
            let snap = IosGetState()
            DispatchQueue.main.async {
                // Во время свитча сети держим «Подключение» и не трогаем поллинг,
                // пока performReconnect не поднимет сессию заново.
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
                let active = (st == "connecting" || st == "connected")
                self.isRunning = active
                if !active {
                    self.stopPolling()
                    self.audio.stop()
                }
            }
        }
    }

    private func stopPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
}

enum AppError: LocalizedError {
    case noConfig
    var errorDescription: String? { "Конфиг не загружен" }
}
