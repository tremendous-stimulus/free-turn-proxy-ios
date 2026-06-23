import Foundation

struct FreeTurnConfig {
    // Ссылку на VK-звонок в файле не храним — она всегда берётся из инпута
    // «Ссылка на VK звонок» и проставляется при загрузке.
    var link: String = ""
    let peer: String
    let dns: String?
    let listen: String?
    var transport: String = "tcp"
    var obfKey: String = ""
    var manualCaptcha: Bool = false
}
