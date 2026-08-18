import Foundation

// Оркестрация WG-in-WG для одного профиля (план vpn-lexical-rossum.md, фаза
// 5.3/5.4): ЛОКАЛЬНАЯ половина (порт, ключи responder'а) общая на всё
// приложение — один KeychainLocalWGConfigStore без ключа; ВНЕШНИЙ конфиг
// VPN-сервера привязан к профилю (ExternalWGConfigStoring, ключ — id
// профиля), потому что у разных профилей могут быть разные серверы. Схема
// AllowedIPs зафиксирована на .withoutVK — спайк Фазы 0 провалил
// .fullInternet, выбора пользователю больше не показываем.
//
// Черновой режим: все методы ниже (кроме persist/discard) правят только
// local/external в памяти, в Keychain ничего не пишут. Экран профиля
// (TunnelDetailView) зовёт persist() по галочке и discard() по крестику —
// «загрузка» реального конфига сервера, смена имени/порта и перегенерация
// ключей должны исчезать бесследно, если пользователь передумал и закрыл
// экран крестиком.
@MainActor
final class LocalWGConfigViewModel: ObservableObject {
    @Published var local: LocalWGConfig?
    @Published var external: ExternalWGConfig?
    @Published var errorText: String?
    @Published var sending = false
    @Published var exportURL: URL?
    @Published var showExport = false
    @Published var nameText: String = ""
    @Published var portText: String = ""

    private let localStore: LocalWGConfigStoring
    private let externalStore: ExternalWGConfigStoring
    private let profileID: UUID
    // Снимок того, что реально лежит в Keychain на момент открытия экрана —
    // база для isDirty и то, к чему откатывает discard().
    private let committedLocal: LocalWGConfig?
    private let committedExternal: ExternalWGConfig?

    var hasServerConfig: Bool { !(external?.remoteConfText.isEmpty ?? true) }
    var isDirty: Bool { local != committedLocal || external != committedExternal }

    init(profileID: UUID,
         localStore: LocalWGConfigStoring = KeychainLocalWGConfigStore(),
         externalStore: ExternalWGConfigStoring = KeychainExternalWGConfigStore()) {
        self.profileID = profileID
        self.localStore = localStore
        self.externalStore = externalStore
        let loadedLocal = localStore.load()
        let loadedExternal = externalStore.load(for: profileID)
        committedLocal = loadedLocal
        committedExternal = loadedExternal
        local = loadedLocal
        external = loadedExternal
        nameText = loadedLocal?.name ?? ""
        portText = String(loadedLocal?.port ?? LocalWGConfig.defaultPort)
    }

    // Добавить или заменить конфиг ВНЕШНЕГО сервера — привязан к этому
    // профилю. Локальная половина, если её ещё не было (самый первый профиль
    // в режиме WG-in-WG), заводится тут же со случайными именем/портом.
    func addOrReplace(rawConfigText: String) {
        do {
            external = try ExternalWGConfigFactory.make(remoteConfText: rawConfigText)
            if local == nil {
                let generated = LocalWGConfigFactory.make()
                local = generated
                nameText = generated.name
                portText = String(generated.port)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    // Новые ключи локальной половины — на случай, если пользователь хочет
    // ротацию. Общие на все профили, поэтому затрагивают весь локальный
    // туннель, а не только текущий профиль.
    func regenerateKeys() {
        guard let local else { return }
        self.local = LocalWGConfigFactory.make(name: local.name, port: local.port)
    }

    func commitName() {
        guard var local else { return }
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { nameText = local.name; return }
        guard trimmed != local.name else { return }
        local.name = trimmed
        self.local = local
    }

    func commitPort() {
        guard var local else { return }
        guard let port = Int(portText), (1...65535).contains(port) else {
            portText = String(local.port)
            return
        }
        guard port != local.port else { return }
        local.port = port
        self.local = local
    }

    // Собрать локальный .conf и отдать наружу через share sheet.
    // sentAt правится только в памяти — станет постоянным вместе со всем
    // остальным черновиком по persist().
    func sendToAmneziaWG() {
        guard let local, let external else { return }
        sending = true
        errorText = nil
        let safeName = local.name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined()
        Task.detached {
            do {
                // AllowedIPs больше не считается вычитанием подсетей: весь
                // трафик забирается в туннель, а что уходит мимо — решает
                // роутер ftun в рантайме (план, фаза 5.2).
                let text = LocalConfigBuilder.build(local: local, external: external, allowedIPs: LocalConfigBuilder.allowedIPsAll)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(safeName.isEmpty ? "tunnel" : safeName)
                    .appendingPathExtension("conf")
                try text.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    var updated = external
                    updated.sentAt = Date()
                    self.external = updated
                    self.exportURL = url
                    self.showExport = true
                    self.sending = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.sending = false
                }
            }
        }
    }

    // Вызывается экраном профиля по нажатию галочки.
    func persist() {
        if local != committedLocal, let local { localStore.save(local) }
        if external != committedExternal, let external { externalStore.save(external, for: profileID) }
    }

    // Вызывается экраном профиля по нажатию крестика — откатывает все правки
    // этого захода (загрузку конфига сервера, смену имени/порта, перегенерацию).
    func discard() {
        local = committedLocal
        external = committedExternal
        nameText = committedLocal?.name ?? ""
        portText = String(committedLocal?.port ?? LocalWGConfig.defaultPort)
    }
}
