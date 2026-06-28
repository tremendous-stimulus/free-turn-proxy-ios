import SwiftUI

struct MainTabView: View {
    @ObservedObject private var store = ConfigStore.shared
    @ObservedObject private var captcha = CaptchaController.shared
    @State private var tab = 0
    @AppStorage(DefaultsKeys.telemetryOnboarded) private var onboarded = false
    @State private var certDaysLeft: Int?
    @State private var availableUpdate: String?

    private static let warnThreshold = 3

    private enum ActiveBanner {
        case cert(Int)
        case update(String)
    }

    private var activeBannerKind: ActiveBanner? {
        if let days = certDaysLeft, days <= Self.warnThreshold { return .cert(days) }
        if let version = availableUpdate { return .update(version) }
        return nil
    }

    private var isBannerVisible: Bool { activeBannerKind != nil }

    @ViewBuilder private var activeBanner: some View {
        switch activeBannerKind {
        case .cert(let days): CertExpiryBanner(daysLeft: days)
        case .update(let version): UpdateBanner(latestVersion: version)
        case nil: EmptyView()
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
                        .tag(UIState.tunnelTabTag)

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
                .onChange(of: tab) { newTab in UIState.currentTab = newTab }
                .onAppear { UIState.currentTab = tab }
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
