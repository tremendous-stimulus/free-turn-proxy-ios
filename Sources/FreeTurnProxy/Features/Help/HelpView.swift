import SwiftUI

struct HelpView: View {
    private let supportURL = URL(string: "https://t.me/freeturnproxy_ios_help_bot")!

    private let faq: [(q: String, a: String)] = [
        ("Как работает приложение?",
         "Оно устанавливает соединение с сервером, на котором работает VPN, через VK-звонок. Это соединение возможно даже когда включены белые списки интернета. Подробнее: https://github.com/samosvalishe/free-turn-proxy"),
        ("Я подключился через вкладку «Туннель», но зарубежные сервисы всё еще блокируются. Что делать?",
         "Это приложение — не VPN. Подключение через вкладку «Туннель» само по себе ничего не разблокирует, а лишь позволяет установить соединение с сервером, на котором работает VPN. Для того, чтобы разблокировать сервисы, нужно подключиться к этому VPN, предварительно сгенерировав конфигурацию для него во вкладке «Конфиг VPN»."),
        ("С чего начать?",
         "1. Вкладка «Туннель»: сгенерируйте или вставьте ссылку на VK-звонок, загрузите файл конфигурации либо настройте подключение вручную через кнопку «+».\n2. Вкладка «Конфиг VPN»: отсканируйте QR-код с конфигурацией VPN, введите название конфигурации и откройте готовый файл в AmneziaWG/WireGuard через кнопку «Поделиться» (либо сохраните файл конфигурации и импортируйте его в AmneziaWG/WireGuard).\n3. Включите подключение к новому конфигу в AmneziaWG/WireGuard."),
        ("VPN не работает или перестал работать",
         "Проверьте: вверху вкладки «Туннель» горит зелёная точка; адрес сервера и ключ введены без ошибок; подключение в AmneziaWG/WireGuard включено; на телефоне есть обычный интернет. Если всё верно — попробуйте всё выключить и включить заново. Если это не помогло — напишите в поддержку."),
        ("Нужно ли держать приложение открытым?",
         "После того как во вкладке «Туннель» высветилось «Подключено», приложение можно свернуть"),
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
            }
            .padding()
        }
        .navigationTitle("Помощь")
        .navigationBarTitleDisplayMode(.large)
    }
}
