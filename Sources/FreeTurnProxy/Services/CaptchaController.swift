import Foundation
import SwiftUI
import UIKit
import UserNotifications
import Ios

// Ручное решение VK Smart Captcha. Когда авто-решатель в Go не справился, он
// поднимает локальный прокси VK-страницы и через gomobile зовёт show(url:) —
// мы показываем WebView на этот адрес. Пользователь проходит captcha, Go-прокси
// сам ловит success_token из ответов VK, после чего Go зовёт hide().
//
// pendingURL держит активную captcha, пока Go ждёт решения (даже если попап
// закрыли) — это даёт кнопку «Открыть captcha» и пуш в фоне. isPresented
// управляет показом самого попапа.
final class CaptchaController: NSObject, ObservableObject {
    static let shared = CaptchaController()

    @Published var pendingURL: URL?
    @Published var isPresented = false

    private let notifID = "captcha-needed"

    private override init() { super.init() }

    func registerNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Go дёргает из своей горутины — мутации @Published уводим на главный поток.
    func show(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.main.async {
            self.pendingURL = url
            withAnimation(.easeInOut(duration: 0.2)) { self.isPresented = true }
            // В фоне (интент/автопереподключение) пользователь не увидит попап —
            // шлём пуш, по тапу вернёмся и откроем captcha.
            if UIApplication.shared.applicationState != .active {
                self.postNeedsCaptchaNotification()
            }
        }
    }

    func hide() {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.pendingURL = nil
                self.isPresented = false
            }
            let c = UNUserNotificationCenter.current()
            c.removeDeliveredNotifications(withIdentifiers: [self.notifID])
            c.removePendingNotificationRequests(withIdentifiers: [self.notifID])
        }
    }

    // Кнопка «Открыть captcha» и тап по пушу — заново показать попап, пока
    // captcha ещё актуальна.
    func reopen() {
        DispatchQueue.main.async {
            guard self.pendingURL != nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.isPresented = true }
        }
    }

    private func postNeedsCaptchaNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Нужно решить captcha"
        content.body = "Откройте приложение и пройдите проверку, чтобы продолжить подключение."
        content.sound = .default
        let req = UNNotificationRequest(identifier: notifID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

extension CaptchaController: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        reopen()
        completionHandler()
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
        CaptchaController.shared.registerNotifications()
    }
}
