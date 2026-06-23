import SwiftUI

struct MainTabView: View {
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TunnelView()
                .tabItem { Label("Туннель", systemImage: "arrow.up.arrow.down") }
                .tag(0)

            NavigationStack {
                ConfigView(isSelected: tab == 1)
            }
            .tabItem { Label("Конфиг VPN", systemImage: "network") }
            .tag(1)

            NavigationStack {
                LogsView()
            }
            .tabItem { Label("Логи", systemImage: "doc.text") }
            .tag(2)

            NavigationStack {
                HelpView()
            }
            .tabItem { Label("Помощь", systemImage: "questionmark.circle") }
            .tag(3)
        }
        .onChange(of: store.pendingImport) { cfg in
            // Открыли .freeturn — показываем вкладку «Туннель», там откроется редактор.
            if cfg != nil { tab = 0 }
        }
        .sheet(item: $captcha.request) { req in
            CaptchaSolveView(url: req.url)
        }
    }
}
