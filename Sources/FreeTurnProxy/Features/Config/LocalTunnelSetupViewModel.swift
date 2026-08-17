import Foundation

// Оркестрация двух карточек Фазы 3 (план vpn-lexical-rossum.md): профиль
// живёт в Keychain (LocalTunnelProfileStoring), привязан к конкретному
// SavedConfig (TURN-релею) через wgProfileID. Схема AllowedIPs зафиксирована
// на .withoutVK — спайк Фазы 0 провалил .fullInternet, выбора пользователю
// больше не показываем.
@MainActor
final class LocalTunnelSetupViewModel: ObservableObject {
    @Published var profile: LocalTunnelProfile?
    @Published var errorText: String?
    @Published var sending = false
    @Published var exportURL: URL?
    @Published var showExport = false

    // Порт апстрим-релея при включённом WG-in-WG (план, «Порты меняются
    // местами») — локальный responder занимает 127.0.0.1:9000.
    static let relayListenAddr = "127.0.0.1:9001"

    private let savedConfigID: UUID
    private let store: ConfigStore
    private let profiles: LocalTunnelProfileStoring

    init(savedConfig: SavedConfig, store: ConfigStore = .shared,
         profiles: LocalTunnelProfileStoring = KeychainLocalTunnelProfileStore()) {
        self.savedConfigID = savedConfig.id
        self.store = store
        self.profiles = profiles
        if let id = savedConfig.wgProfileID {
            profile = profiles.load(id)
        }
    }

    // Шаг 1: добавить или заменить реальный конфиг. Ключи детей генерируются
    // заново при замене (id профиля переиспользуется, чтобы не плодить
    // висячие записи в Keychain) — сервер увидит нового клиента с чистого
    // листа, это ожидаемо для «заменить конфиг».
    func addOrReplace(rawConfigText: String) {
        do {
            let newProfile = try LocalTunnelProfileFactory.make(id: profile?.id ?? UUID(), remoteConfText: rawConfigText)
            profiles.save(newProfile)
            profile = newProfile
            guard var cfg = store.configs.first(where: { $0.id == savedConfigID }) else { return }
            cfg.useLocalTunnel = true
            cfg.wgProfileID = newProfile.id
            cfg.listen = Self.relayListenAddr
            store.update(cfg)
        } catch {
            errorText = error.localizedDescription
        }
    }

    // Шаг 2: собрать локальный .conf и отдать наружу через share sheet.
    // Тяжёлая часть (фетч VK-префиксов) — вне main, как в ConfigViewModel.generate.
    func sendToAmneziaWG() {
        guard let profile else { return }
        sending = true
        errorText = nil
        let fileName = store.configs.first(where: { $0.id == savedConfigID })?.name ?? "tunnel"
        let safeName = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined()
        Task.detached {
            do {
                let allowedIPs = try await AllowedIPsBuilder.build(scheme: .withoutVK)
                let text = LocalConfigBuilder.build(profile: profile, allowedIPs: allowedIPs)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(safeName.isEmpty ? "tunnel" : safeName)
                    .appendingPathExtension("conf")
                try text.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    var updated = profile
                    updated.sentAt = Date()
                    self.profiles.save(updated)
                    self.profile = updated
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
}
