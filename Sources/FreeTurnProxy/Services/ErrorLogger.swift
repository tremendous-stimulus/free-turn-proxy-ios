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

    // MARK: – Unified buffer (Main thread)

    private(set) var entries: [LogEntry] = []
    private var lastGoLogLength = 0
    private var lastShippedIndex = 0

    // Кэп буфера держим скромным: при типичной нагрузке Go-биндинг шлёт логи
    // десятками в секунду, лимит — это аварийный потолок, чтобы при долгом
    // отсутствии сети/телеметрии буфер не разъедал память. 10к × ~250 байт ≈ 2.5 МБ.
    static let maxEntries = 10_000

    var displayLogs: String { entries.map(\.display).joined(separator: "\n") }

    // MARK: – Ingestion

    // Go logs: "HH:MM:SS [LEVEL] message" — время считается UTC (per spec).
    func ingestGoLogs(_ fullLog: String) {
        let newPart = String(fullLog.dropFirst(lastGoLogLength))
        guard !newPart.isEmpty else { return }
        lastGoLogLength = fullLog.count

        let rawLines = newPart.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let parsed = rawLines.compactMap(Self.parseGoLine)
        entries.append(contentsOf: parsed)
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

    func resetGoPosition() { lastGoLogLength = 0 }

    func clear() {
        entries = []
        lastGoLogLength = 0
        lastShippedIndex = 0
    }

    // MARK: – Parsing

    private static let goLineRegex = try! NSRegularExpression(
        pattern: #"^(\d{2}):(\d{2}):(\d{2}) \[(DBG|INF|WRN|ERR)\] (.+)$"#
    )

    // Форматтер для отображения в локальной TZ (не задаём timeZone — берётся системная).
    private static let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // UTC-форматтер для формирования времени из Go-строки.
    private static let utcDisplayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // Кешируем Calendar — создание Calendar затратно, но todayUTC вычисляется свежим при каждом вызове.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    static func parseGoLine(_ raw: String) -> LogEntry? {
        let ns = raw as NSString
        guard let m = goLineRegex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 6 else { return nil }

        let hh = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let mm = Int(ns.substring(with: m.range(at: 2))) ?? 0
        let ss = Int(ns.substring(with: m.range(at: 3))) ?? 0
        let level = ns.substring(with: m.range(at: 4))
        let message = ns.substring(with: m.range(at: 5))

        // Собираем Date из компонентов в UTC (Go логирует в UTC).
        let cal = utcCalendar
        let todayUTC = cal.dateComponents([.year, .month, .day], from: Date())
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = todayUTC.year; comps.month = todayUTC.month; comps.day = todayUTC.day
        comps.hour = hh; comps.minute = mm; comps.second = ss
        guard var date = cal.date(from: comps) else { return nil }

        // UTC-полночь: если собранная дата оказалась в будущем больше чем на 5 мин,
        // значит лог был записан в прошлые сутки — сдвигаем назад на 1 день.
        if date > Date().addingTimeInterval(300) {
            date = cal.date(byAdding: .day, value: -1, to: date) ?? date
        }

        let displayTime = displayFmt.string(from: date)   // локальная TZ телефона
        let utcISO = isoFmt.string(from: date)

        return LogEntry(
            display: "\(displayTime) [\(level)] \(message)",
            utcISO: utcISO,
            level: level,
            message: message
        )
    }

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
