import Foundation
import Network

// Единый буфер логов: Go-библиотека + события приложения.
// Все мутации — на Main thread.
final class ErrorLogger {
    static let shared = ErrorLogger()

    static let uploadURL = "https://telemetry.free-turn-proxy-ios.workers.dev/"

    let sessionTag: String = String(UUID().uuidString.prefix(8).lowercased())

    static let clientId: String = {
        if let v = UserDefaults.standard.string(forKey: DefaultsKeys.errorLoggerClientId) { return v }
        let new = String(UUID().uuidString.prefix(8).lowercased())
        UserDefaults.standard.set(new, forKey: DefaultsKeys.errorLoggerClientId)
        return new
    }()

    // MARK: – LogEntry

    struct LogEntry {
        let display: String  // "HH:MM:SS [LEVEL] message" в локальной TZ телефона
        let utcISO: String   // "2026-06-26T22:04:27Z" — для телеметрии
        let level: String    // "DBG" | "INF" | "WRN" | "ERR"
        let message: String  // сообщение без префикса времени и уровня
    }

    // Порог отображения в LogsView — фильтр чисто UI-шный, на shipBatch()
    // (отправку в телеметрию) не влияет: там уходит всё, независимо от того,
    // что выбрано в настройках экрана логов.
    enum LogLevel: String, CaseIterable, Identifiable {
        case dbg = "DBG", inf = "INF", wrn = "WRN", err = "ERR"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dbg: return "Все"
            case .inf: return "Инфо и выше"
            case .wrn: return "Предупреждения и выше"
            case .err: return "Только ошибки"
            }
        }

        fileprivate var order: Int {
            switch self {
            case .dbg: return 0
            case .inf: return 1
            case .wrn: return 2
            case .err: return 3
            }
        }
    }

    // MARK: – Unified buffer (Main thread)

    private(set) var entries: [LogEntry] = []
    private var lastShippedIndex = 0

    // Кэп буфера держим скромным: при типичной нагрузке Go-биндинг шлёт логи
    // десятками в секунду, лимит — это аварийный потолок, чтобы при долгом
    // отсутствии сети/телеметрии буфер не разъедал память. 10к × ~250 байт ≈ 2.5 МБ.
    static let maxEntries = 10_000

    var displayLogs: String { entries.map(\.display).joined(separator: "\n") }

    // Неизвестный уровень (в буфере такого пока не бывает — level всегда из
    // levelMap/appendAppLine — но на случай будущего расширения) не режем.
    func displayLogs(minLevel: LogLevel) -> String {
        entries
            .filter { LogLevel(rawValue: $0.level).map { $0.order >= minLevel.order } ?? true }
            .map(\.display)
            .joined(separator: "\n")
    }

    // MARK: – Ingestion

    // Уровни, с которыми ядро v2 шлёт EventSink.OnLog — маппим на прежние
    // трёхбуквенные, чтобы не трогать Cloudflare Worker и дашборды Loki.
    private static let levelMap: [String: String] = [
        "debug": "DBG", "info": "INF", "warn": "WRN", "error": "ERR",
    ]

    // Пуш от EventSinkBridge.onLog: уровень и время приходят уже готовыми,
    // разбирать текст строки (как в v1.8.0) больше не нужно.
    func ingest(level: String, message: String, unixMillis: Int64) {
        let mapped = Self.levelMap[level] ?? level.uppercased()
        let date = Date(timeIntervalSince1970: Double(unixMillis) / 1000)
        let display = "\(Self.displayFmt.string(from: date)) [\(mapped)] \(message)"
        let utcISO = Self.isoFmt.string(from: date)
        entries.append(LogEntry(display: display, utcISO: utcISO, level: mapped, message: message))
        enforceMaxEntries()
    }

    // App-level события.
    func appendAppLine(level: String, message: String) {
        let now = Date()
        let display = "\(Self.displayFmt.string(from: now)) [\(level)] [App] \(message)"
        let utcISO = Self.isoFmt.string(from: now)
        entries.append(LogEntry(display: display, utcISO: utcISO, level: level, message: "[App] \(message)"))
        enforceMaxEntries()
    }

    // Срезает голову буфера до maxEntries и корректирует lastShippedIndex на
    // ту же величину — иначе после ужима индекс «уходит» в правую часть
    // массива и при следующем shipBatch мы пропустим только что добавленные
    // строки (dropFirst(lastShippedIndex) даст пустой слайс).
    private func enforceMaxEntries() {
        guard entries.count > Self.maxEntries else { return }
        let overflow = entries.count - Self.maxEntries
        entries.removeFirst(overflow)
        lastShippedIndex = max(0, lastShippedIndex - overflow)
    }

    func clear() {
        entries = []
        lastShippedIndex = 0
    }

    // MARK: – Форматтеры

    // Форматтер для отображения в локальной TZ (не задаём timeZone — берётся системная).
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: – Ship

    func shipBatch() {
        guard UserDefaults.standard.object(forKey: DefaultsKeys.telemetryEnabled) as? Bool ?? true else {
            lastShippedIndex = entries.count
            return
        }
        let toShip = Array(entries.dropFirst(lastShippedIndex))
        guard !toShip.isEmpty else { return }
        lastShippedIndex = entries.count

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let payload: [String: Any] = [
            "appVersion": appVersion,
            "session": sessionTag,
            "client": Self.clientId,
            "entries": toShip.map { [
                "utc": $0.utcISO,
                "level": $0.level,
                "msg": $0.message,
            ] },
        ]
        uploadQueue.async { [weak self] in
            self?.persist(payload)
            self?.uploadIfPossible()
        }
    }

    func flushOnLaunch() {
        uploadQueue.async { [weak self] in self?.uploadIfPossible() }
    }

    // MARK: – Persistence & upload

    private let uploadQueue = DispatchQueue(label: "com.freeturn.errorlog", qos: .utility)
    private var networkMonitor: NWPathMonitor?
    private var networkAvailable = false
    private var pendingUpload = false
    private var retryAttempt = 0
    private var retryWork: DispatchWorkItem?

    private init() { startNetworkWatch() }

    private var logsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("log_batches", isDirectory: true)
    }

    private func persist(_ payload: [String: Any]) {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let name = "\(Date().timeIntervalSince1970)-\(UUID().uuidString).json"
        try? data.write(to: logsDir.appendingPathComponent(name))
    }

    private static let batchTTL: TimeInterval = 600 // 10 минут

    private func allBatchFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }

    private func pruneExpired() {
        let cutoff = Date().timeIntervalSince1970 - Self.batchTTL
        for url in allBatchFiles() {
            let ts = Double(url.deletingPathExtension().lastPathComponent.split(separator: "-").first ?? "") ?? 0
            if ts > 0 && ts < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func pendingFiles() -> [URL] {
        pruneExpired()
        return allBatchFiles()
    }

    private func startNetworkWatch() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            self?.uploadQueue.async {
                self?.networkAvailable = available
                if available { self?.retryAttempt = 0; self?.uploadIfPossible() }
            }
        }
        m.start(queue: DispatchQueue(label: "com.freeturn.errorlog.net"))
        networkMonitor = m
    }

    private func uploadIfPossible() {
        guard !Self.uploadURL.isEmpty, networkAvailable, !pendingUpload else { return }
        let files = pendingFiles()
        guard !files.isEmpty else { return }
        pendingUpload = true
        upload(files: files) { [weak self] anyFailed in
            guard let self else { return }
            self.pendingUpload = false
            anyFailed ? self.scheduleRetry() : (self.retryAttempt = 0)
        }
    }

    private func scheduleRetry() {
        guard networkAvailable else { return }
        let delay = min(pow(2.0, Double(retryAttempt)) * 2.0, 60.0)
        retryAttempt += 1
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.uploadIfPossible() }
        retryWork = work
        uploadQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // Загружаем файлы по одному — параллельная отправка перегружает мобильный канал
    // и приводит к NSURLErrorNetworkConnectionLost (-1005).
    private func upload(files: [URL], completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: Self.uploadURL) else { completion(false); return }
        uploadNext(files: files[...], url: url, anyFailed: false, completion: completion)
    }

    private func uploadNext(files: ArraySlice<URL>, url: URL, anyFailed: Bool, completion: @escaping (Bool) -> Void) {
        guard let file = files.first else { completion(anyFailed); return }
        let rest = files.dropFirst()
        guard let data = try? Data(contentsOf: file) else {
            uploadNext(files: rest, url: url, anyFailed: anyFailed, completion: completion)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            if ok { try? FileManager.default.removeItem(at: file) }
            self?.uploadQueue.async {
                self?.uploadNext(files: rest, url: url, anyFailed: anyFailed || !ok, completion: completion)
            }
        }.resume()
    }
}
