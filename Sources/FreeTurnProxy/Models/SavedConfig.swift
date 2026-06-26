import Foundation

// Сохранённая конфигурация TURN-сервера. VK-ссылку не храним — она всегда
// берётся из инпута на вкладке «Туннель». Пустые dns/listen означают дефолт.
struct SavedConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var peer: String
    var obfKey: String = ""
    var dns: String = ""
    var listen: String = ""
    var transport: String = "udp"
    // Всегда решать VK captcha вручную (через WebView), минуя авто-решатель.
    var manualCaptcha: Bool = false
}
