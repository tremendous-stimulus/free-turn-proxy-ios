import Foundation
import Network

// Единый буфер логов: Go-библиотека + события приложения.
// Все мутации — на Main thread.
final class ErrorLogger {
    static let shared = ErrorLogger()

    static let uploadURL = "https://telemetry.free-turn-proxy-ios.workers.dev/"

    let sessionTag: String = UUID().uuidString.prefix(8).lowercased().description

    static let clientId: String = {
        let key = "error_logger_client_id"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let new = UUID().uuidString.prefix(8).lowercased().description
        UserDefaults.standard.set(new, forKey: key)
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
    }

    // App-level события.
    func appendAppLine(level: String, message: String) {
        let now = Date()
        let display = "\(Self.displayFmt.string(from: now)) [\(level)] [App] \(message)"
        let utcISO = Self.isoFmt.string(from: now)
        entries.append(LogEntry(display: display, utcISO: utcISO, level: level, message: "[App] \(message)"))
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

    private static func parseGoLine(_ raw: String) -> LogEntry? {
        let ns = raw as NSString
        guard let m = goLineRegex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 6 else { return nil }

        let hh = Int(ns.substring(with: m.range(at: 1))) ?? 0
        let mm = Int(ns.substring(with: m.range(at: 2))) ?? 0
        let ss = Int(ns.substring(with: m.range(at: 3))) ?? 0
        let level = ns.substring(with: m.range(at: 4))
        let message = ns.substring(with: m.range(at: 5))

        // Собираем Date из компонентов в UTC (Go логирует в UTC).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let todayUTC = cal.dateComponents([.year, .month, .day], from: Date())
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = todayUTC.year; comps.month = todayUTC.month; comps.day = todayUTC.day
        comps.hour = hh; comps.minute = mm; comps.second = ss
        guard let date = cal.date(from: comps) else { return nil }

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
        guard UserDefaults.standard.object(forKey: "telemetry_enabled") as? Bool ?? true else {
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

    private func pendingFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
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

    private func upload(files: [URL], completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: Self.uploadURL) else { completion(false); return }
        let group = DispatchGroup()
        var anyFailed = false
        for file in files {
            group.enter()
            guard let data = try? Data(contentsOf: file) else { group.leave(); continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            req.timeoutInterval = 10
            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                let status = (resp as? HTTPURLResponse)?.statusCode
                if status == 200 {
                    try? FileManager.default.removeItem(at: file)
                } else {
                    anyFailed = true
                    let detail: String
                    if let err {
                        detail = err.localizedDescription
                    } else if let data, let body = String(data: data, encoding: .utf8) {
                        detail = "HTTP \(status ?? 0): \(body.prefix(200))"
                    } else {
                        detail = "HTTP \(status ?? 0)"
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.appendAppLine(level: "ERR", message: "telemetry upload failed: \(detail)")
                    }
                }
                self?.uploadQueue.async { group.leave() }
            }.resume()
        }
        group.notify(queue: uploadQueue) { completion(anyFailed) }
    }
}
