import Foundation
import Mobile

@MainActor
final class LogsViewModel: ObservableObject {
    @Published var logs = ""
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        MobileClearLogs()
        logs = ""
    }

    // Сохраняем текущие логи в .txt во временную папку и отдаём URL для шаринга.
    func exportFile() -> URL? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "freeturn-logs-\(fmt.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try logs.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func refresh() {
        let new = MobileGetLogs()
        if new != logs { logs = new }
    }
}
