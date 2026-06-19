import SwiftUI

@main
struct FreeTurnProxyApp: App {
    init() {
        // Свежая установка — стираем токены, пережившие удаление приложения.
        Keychain.wipeSecretsOnFreshInstall()
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
