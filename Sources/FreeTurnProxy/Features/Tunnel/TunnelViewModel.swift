import SwiftUI

@MainActor
final class TunnelViewModel: ObservableObject {
    let proxy = ProxyManager.shared
    let store = ConfigStore.shared

    @Published var errorText: String?
    @Published var shareURL: URL?

    // VK-ссылка (per-session) — персистится под прежним ключом.
    @Published var link: String { didSet { d.set(link, forKey: "manualLink") } }

    // VK-логин для генерации ссылки.
    @Published var creatingCall = false
    @Published var showVKWebFallback = false
    // VK access-token. Персистится в Keychain (учётные данные), не в plist.
    private var vkAuthToken: String? {
        didSet { Keychain.set(vkAuthToken, for: vkTokenKey) }
    }

    private let d = UserDefaults.standard
    private let vkTokenKey = Keychain.vkTokenAccount

    init() {
        link = d.string(forKey: "manualLink") ?? ""
        vkAuthToken = Keychain.get(vkTokenKey)
    }

    // MARK: – Валидация

    var linkError: String? {
        let s = link.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        return Validators.vkLink(s) ? nil : "Ссылка вида https://vk.com/call/join/…"
    }

    var canConnect: Bool {
        guard let c = store.selected else { return false }
        return !link.trimmingCharacters(in: .whitespaces).isEmpty
            && linkError == nil
            && Validators.endpoint(c.peer)
    }

    // MARK: – VK

    func createCall() async {
        guard let token = vkAuthToken else {
            showVKWebFallback = true
            return
        }
        creatingCall = true
        defer { creatingCall = false }
        do {
            link = try await vkCreateCall(token: token)
        } catch {
            // Сбрасываем токен только когда VK сам сказал, что он невалиден
            // (error_code 5 — User authorization failed). Сетевые сбои и
            // прочее не должны стирать сохранённый в Keychain токен.
            if case VKCallError.apiError(5, _) = error {
                vkAuthToken = nil
                showVKWebFallback = true  // токен протух — сразу открываем логин
                return
            }
            errorText = error.localizedDescription
        }
    }

    func onVKToken(_ token: String) {
        vkAuthToken = token
        Task { await createCall() }
    }

    // MARK: – Подключение

    func toggle() {
        if proxy.isRunning { proxy.stop() } else { connect() }
    }

    private func connect() {
        do {
            try TunnelController.connect()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: – Поделиться

    func share(_ c: SavedConfig) {
        guard let url = store.exportFile(c) else {
            errorText = "Не удалось подготовить файл конфигурации"
            return
        }
        shareURL = url
    }
}
