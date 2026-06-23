import Foundation
import Ios

// Ручное решение VK Smart Captcha. Когда авто-решатель в Go не справился, он
// поднимает локальный прокси VK-страницы и через gomobile зовёт show(url:) —
// мы показываем WebView на этот адрес. Пользователь проходит captcha, Go-прокси
// сам ловит success_token из ответов VK, после чего Go зовёт hide().

struct CaptchaRequest: Identifiable {
    let id = UUID()
    let url: URL
}

// Источник состояния для UI: непустой request -> показываем sheet с captcha.
final class CaptchaController: ObservableObject {
    static let shared = CaptchaController()
    @Published var request: CaptchaRequest?

    private init() {}

    // Go дёргает из своей горутины — мутации @Published уводим на главный поток.
    func show(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.main.async { self.request = CaptchaRequest(url: url) }
    }

    func hide() {
        DispatchQueue.main.async { self.request = nil }
    }
}

// Реализация gomobile-протокола IosCaptchaPresenter (Go -> Swift колбэк).
// В Swift протокол импортируется с суффиксом Protocol (одноимённый класс-обёртка
// занимает имя IosCaptchaPresenter).
private final class CaptchaPresenterBridge: NSObject, IosCaptchaPresenterProtocol {
    func show(_ url: String?) { CaptchaController.shared.show(url ?? "") }
    func hide() { CaptchaController.shared.hide() }
}

enum CaptchaBridge {
    // Go хранит только ссылку на протокол — держим презентер живым здесь.
    private static var presenter: CaptchaPresenterBridge?

    static func register() {
        let p = CaptchaPresenterBridge()
        presenter = p
        IosSetCaptchaPresenter(p)
    }
}
