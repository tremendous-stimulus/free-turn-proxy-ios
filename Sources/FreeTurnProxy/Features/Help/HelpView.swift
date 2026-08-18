import SwiftUI

struct HelpView: View {
    @Environment(\.isBannerVisible) private var isBannerVisible
    private let supportURL = URL(string: "https://t.me/freeturnproxy_ios_help_bot")!

    // Скрытая диагностика: 5 тапов по версии показывают ID приложения и
    // сессии — те же, что уходят с логами в телеметрию, полезно сверить
    // при разборе жалобы в поддержку.
    @State private var versionTapCount = 0
    @State private var showDiagnosticIDs = false

    private let faq: [(q: String, a: String)] = [
        ("Как работает приложение?",
         "Оно устанавливает соединение с сервером, на котором работает VPN, через VK-звонок. Это соединение возможно даже когда включены белые списки интернета. Подробнее: https://github.com/samosvalishe/free-turn-proxy"),
        ("Я подключился через вкладку «Профили», но зарубежные сервисы всё еще блокируются. Что делать?",
         "Это приложение — не VPN. Подключение через вкладку «Профили» само по себе ничего не разблокирует, а лишь позволяет установить соединение с сервером, на котором работает VPN. Для того, чтобы разблокировать сервисы, нужно подключиться к этому VPN, предварительно настроив его — откройте нужный профиль в списке, раздел «VPN подключение»."),
        ("С чего начать?",
         "1. Вкладка «Профили»: сгенерируйте или вставьте ссылку на VK-звонок, загрузите файл профиля либо настройте подключение вручную через кнопку «+».\n2. Откройте добавленный профиль в списке, раздел «VPN подключение»: отсканируйте QR-код с конфигурацией вашего VPN-сервера и откройте готовый файл в AmneziaWG/WireGuard через кнопку «Поделиться» (либо сохраните файл и импортируйте его вручную).\n3. Включите подключение к новому конфигу в AmneziaWG/WireGuard."),
        ("VPN не работает или перестал работать",
         "Проверьте: вверху вкладки «Профили» горит зелёная точка; адрес сервера и ключ введены без ошибок; подключение в AmneziaWG/WireGuard включено; на телефоне есть обычный интернет. Если всё верно — попробуйте всё выключить и включить заново. Если это не помогло — напишите в поддержку."),
        ("Нужно ли держать приложение открытым?",
         "После того как во вкладке «Профили» высветилось «Подключено», приложение можно свернуть"),
        ("Нужно ли подключаться к VK-звонку? Сколько действует ссылка на звонок?", "Подключаться к звонку не нужно. Ссылка на звонок действует бессрочно, повторная генерация перед каждым подключением не требуется.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(faq.indices, id: \.self) { i in
                    DisclosureGroup {
                        Text(faq[i].a)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    } label: {
                        Text(faq[i].q)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }

                VStack(spacing: 12) {
                    Text("Остались вопросы?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: supportURL) {
                        Label {
                            Text("Написать в поддержку")
                        } icon: {
                            Image("TelegramLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                HStack(spacing: 6) {
                    Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                versionTapCount = 0
                                showDiagnosticIDs = true
                            }
                        }
                    Text("·")
                    Link("GitHub", destination: URL(string: "https://github.com/tremendous-stimulus/free-turn-proxy-ios")!)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Помощь")
        .navigationBarTitleDisplayMode(isBannerVisible ? .inline : .large)
        .alert("Диагностика", isPresented: $showDiagnosticIDs) {
            Button("Скопировать") { UIPasteboard.general.string = diagnosticIDsText }
            Button("OK") {}
        } message: {
            Text(diagnosticIDsText)
        }
    }

    private var diagnosticIDsText: String {
        "ID приложения: \(ErrorLogger.clientId)\nID сессии: \(ErrorLogger.shared.sessionTag)"
    }
}
