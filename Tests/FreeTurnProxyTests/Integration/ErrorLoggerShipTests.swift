import XCTest
@testable import FreeTurnProxy

// ErrorLogger — singleton, поэтому в каждом тесте подчищаем общее состояние:
// буфер записей, телеметрию-флаг, директорию батчей и MockURLProtocol.
final class ErrorLoggerShipTests: XCTestCase {

    private static let telemetryHost = "telemetry.free-turn-proxy-ios.workers.dev"

    private var logsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("log_batches", isDirectory: true)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.register()
        UserDefaults.standard.set(true, forKey: "telemetry_enabled")
        cleanLogsDir()
        ErrorLogger.shared.clear()
    }

    override func tearDown() {
        MockURLProtocol.unregister()
        cleanLogsDir()
        ErrorLogger.shared.clear()
        super.tearDown()
    }

    private func cleanLogsDir() {
        try? FileManager.default.removeItem(at: logsDir)
    }

    private func pendingFileCount() -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.count
    }

    // MARK: – telemetry_enabled=false → батч не пишется

    func test_telemetryDisabled_nothingPersisted() async {
        UserDefaults.standard.set(false, forKey: "telemetry_enabled")
        await MainActor.run {
            ErrorLogger.shared.appendAppLine(level: "INF", message: "hello")
            ErrorLogger.shared.shipBatch()
        }
        // Дать uploadQueue время отработать.
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(pendingFileCount(), 0)
    }

    // MARK: – 200 → файл удалён

    func test_successfulUpload_removesPersistedFile() async {
        MockURLProtocol.stub(host: Self.telemetryHost,
                             with: .http(status: 200, body: Data()))

        await MainActor.run {
            ErrorLogger.shared.appendAppLine(level: "INF", message: "hello")
            ErrorLogger.shared.shipBatch()
        }

        let exp = expectation(for: NSPredicate { [weak self] _, _ in
            self?.pendingFileCount() == 0
        }, evaluatedWith: nil)
        await fulfillment(of: [exp], timeout: 8)
    }

    // MARK: – 500 → файл остаётся для ретрая

    func test_failedUpload_keepsFile() async {
        MockURLProtocol.stub(host: Self.telemetryHost,
                             with: .http(status: 500, body: Data()))

        await MainActor.run {
            ErrorLogger.shared.appendAppLine(level: "ERR", message: "boom")
            ErrorLogger.shared.shipBatch()
        }

        // Дождаться появления файла, потом убедиться что он не удаляется.
        let appears = expectation(for: NSPredicate { [weak self] _, _ in
            self?.pendingFileCount() == 1
        }, evaluatedWith: nil)
        await fulfillment(of: [appears], timeout: 4)

        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertGreaterThanOrEqual(pendingFileCount(), 1)
    }

    // MARK: – TTL: старый файл удаляется без отправки

    func test_expiredBatchFile_deletedWithoutUpload() async {
        // Создаём батч с timestamp из позапрошлой жизни.
        try? FileManager.default.createDirectory(at: logsDir,
                                                 withIntermediateDirectories: true)
        let expiredName = "100.0-\(UUID().uuidString).json"
        let url = logsDir.appendingPathComponent(expiredName)
        try? Data(#"{"entries":[]}"#.utf8).write(to: url)
        XCTAssertEqual(pendingFileCount(), 1)

        // Запросов на upload быть не должно — если они вдруг пойдут, мок 500
        // оставил бы файл живым. Но мы ждём именно удаления TTL-фильтром.
        MockURLProtocol.stub(host: Self.telemetryHost,
                             with: .http(status: 500, body: Data()))

        // Создаём новый батч → uploadIfPossible → pendingFiles() → TTL чистит старый.
        await MainActor.run {
            ErrorLogger.shared.appendAppLine(level: "INF", message: "trigger")
            ErrorLogger.shared.shipBatch()
        }

        let exp = expectation(for: NSPredicate { [weak self] _, _ in
            (self?.pendingFileCount() ?? 99) <= 1
                && !FileManager.default.fileExists(atPath: url.path)
        }, evaluatedWith: nil)
        await fulfillment(of: [exp], timeout: 8)
    }

    // MARK: – Buffer overflow: после ужима lastShippedIndex не должен пропускать новые строки

    // Регресс на «тихо потерянные» строки: после shipBatch индекс уехал к
    // entries.count, потом appendAppLine/ingestGoLogs ужал буфер. Если индекс
    // не сдвинуть на overflow, следующий shipBatch отправит пустой батч и
    // свежие строки уйдут в небытие. Используем mock 500 — файл остаётся на
    // диске после неудачной заливки, можно проверить через его содержимое.
    func test_bufferOverflow_afterShip_doesNotSkipNewEntries() async {
        MockURLProtocol.stub(host: Self.telemetryHost,
                             with: .http(status: 500, body: Data()))

        let cap = ErrorLogger.maxEntries
        await MainActor.run {
            for i in 0..<cap {
                ErrorLogger.shared.appendAppLine(level: "INF", message: "pre-\(i)")
            }
            ErrorLogger.shared.shipBatch()
        }
        // Ждём пока первый батч уйдёт на диск.
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertGreaterThanOrEqual(pendingFileCount(), 1, "первый батч должен лежать на диске")

        let marker = "post-overflow-\(UUID().uuidString)"
        await MainActor.run {
            for _ in 0..<100 {
                ErrorLogger.shared.appendAppLine(level: "INF", message: marker)
            }
            // Buffer должен ужаться до cap.
            XCTAssertEqual(ErrorLogger.shared.entries.count, cap)
            ErrorLogger.shared.shipBatch()
        }
        // Должен появиться второй батч-файл с маркером — это и есть проверка
        // что lastShippedIndex корректно сдвинулся.
        let exp = expectation(for: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let urls = (try? FileManager.default.contentsOfDirectory(at: self.logsDir, includingPropertiesForKeys: nil)) ?? []
            for u in urls where u.pathExtension == "json" {
                if let s = try? String(contentsOf: u, encoding: .utf8), s.contains(marker) { return true }
            }
            return false
        }, evaluatedWith: nil)
        await fulfillment(of: [exp], timeout: 5)
    }
}
