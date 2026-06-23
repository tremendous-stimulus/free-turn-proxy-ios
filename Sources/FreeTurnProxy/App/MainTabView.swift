import SwiftUI

struct MainTabView: View {
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var tab = 0

    var body: some View {
        // Captcha-оверлей — отдельный слой ZStack поверх TabView, а не .overlay
        // внутри него: так тапы по фону не конкурируют с жестами TabView.
        ZStack {
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

            if captcha.isPresented, let url = captcha.pendingURL {
                CaptchaSolveView(url: url) { captcha.isPresented = false }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: captcha.isPresented)
    }
}
