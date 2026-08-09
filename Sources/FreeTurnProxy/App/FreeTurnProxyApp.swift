import SwiftUI

@main
struct FreeTurnProxyApp: App {
    init() {
        // Свежая установка — стираем токены, пережившие удаление приложения.
        Keychain.wipeSecretsOnFreshInstall()
        // Регистрируем push-приёмник событий ядра (стадия, логи, captcha).
        EventSinkBridge.register()
        // Отправляем логи ошибок прошлых сессий, если есть сеть.
        ErrorLogger.shared.flushOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onOpenURL { url in
                    // Открыли .freeturn через «Открыть в…»/Файлы — откроется редактор.
                    ConfigStore.shared.receiveFile(url)
                }
        }
    }
}
