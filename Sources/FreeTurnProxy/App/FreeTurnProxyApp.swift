import SwiftUI

@main
struct FreeTurnProxyApp: App {
    init() {
        // Свежая установка — стираем токены, пережившие удаление приложения.
        Keychain.wipeSecretsOnFreshInstall()
        // Регистрируем push-приёмник событий ядра (стадия, логи, captcha).
        EventSinkBridge.register()
        // Логи локального WG-in-WG модуля (golib/ftun).
        FtunEventSinkBridge.register()
        // Отправляем логи ошибок прошлых сессий, если есть сеть.
        ErrorLogger.shared.flushOnLaunch()
        // «Обновился ли пользователь» определяем ровно один раз — по наличию
        // профилей на первом запуске. Дальше профили могут появиться или
        // исчезнуть, ответ от этого не меняется.
        LaunchState.resolveUpgradedUser(hasConfigs: !ConfigStore.shared.configs.isEmpty)
        LaunchState.recordRun()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onOpenURL { url in
                    if url.scheme == FreeturnLink.scheme {
                        // freeturn://-ссылка (Telegram, Заметки, другое приложение).
                        ConfigStore.shared.receiveLink(url)
                    } else {
                        // Открыли .freeturn через «Открыть в…»/Файлы — откроется редактор.
                        ConfigStore.shared.receiveFile(url)
                    }
                }
        }
    }
}
