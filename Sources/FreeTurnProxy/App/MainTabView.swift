import SwiftUI

struct MainTabView: View {
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var tab = 0
    @AppStorage("telemetry_onboarded") private var onboarded = false
    @State private var certDaysLeft: Int?
    @State private var availableUpdate: String?

    private static let warnThreshold = 3

    private var isBannerVisible: Bool {
        (certDaysLeft.map { $0 <= Self.warnThreshold } ?? false) || availableUpdate != nil
    }

    @ViewBuilder private var activeBanner: some View {
        if let days = certDaysLeft, days <= Self.warnThreshold {
            CertExpiryBanner(daysLeft: days)
        } else if let version = availableUpdate {
            UpdateBanner(latestVersion: version)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            activeBanner

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
                .environment(\.isBannerVisible, isBannerVisible)
                .onChange(of: store.pendingImport) { cfg in
                    if cfg != nil { tab = 0 }
                }

                if captcha.isPresented, let url = captcha.pendingURL {
                    CaptchaSolveView(url: url) {
                        withAnimation(.easeInOut(duration: 0.2)) { captcha.isPresented = false }
                    }
                }
            }
        }
        .onAppear {
            certDaysLeft = CertificateChecker.daysUntilExpiry()
            Task { availableUpdate = await UpdateChecker.fetchLatestVersion() }
        }
        .alert("Сбор технических данных", isPresented: Binding(
            get: { !onboarded },
            set: { if !$0 { onboarded = true } }
        )) {
            Button("Понятно") { onboarded = true }
        } message: {
            Text("Приложение анонимно отправляет технические логи подключения — это помогает находить и исправлять сбои. Личные данные не передаются.\n\nОтключить можно в настройках вкладки «Логи».")
        }
    }
}
