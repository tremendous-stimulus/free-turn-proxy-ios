import SwiftUI

@MainActor
final class TunnelViewModel: ObservableObject {
    let proxy = ProxyManager.shared
    let store: ConfigStore

    @Published var errorText: String?
    @Published var shareURL: URL?

    // VK-ссылки — общий пул для подключения, персистятся через ManualLinks.
    // Правятся через VKLinksEditorView (кнопка «Редактировать VK-ссылки»).
    @Published var links: [String] { didSet { ManualLinks.current = links } }

    // VK-логин для генерации ссылки.
    @Published var creatingCall = false
    @Published var showVKWebFallback = false
    // VK access-token. Персистится в Keychain (учётные данные), не в plist.
    // internal (не private) — тесты устанавливают напрямую, минуя Keychain.
    var vkAuthToken: String? {
        didSet { Keychain.set(vkAuthToken, for: vkTokenKey) }
    }

    private let vkTokenKey = Keychain.vkTokenAccount
    private let session: URLSession

    init(session: URLSession = .shared, store: ConfigStore = .shared) {
        self.session = session
        self.store = store
        links = ManualLinks.current
        vkAuthToken = Keychain.get(vkTokenKey)
    }

    var canConnect: Bool {
        guard let c = store.selected else { return false }
        return !links.isEmpty && Validators.endpoint(c.peer)
    }

    // MARK: – VK

    // Генерирует ровно count ссылок и возвращает их — не трогает links сама
    // по себе. Вызывающая сторона (VKLinksEditorView) решает, что делать с
    // результатом: там это черновой список, который применяется только по
    // «Сохранить». Останавливается на первой ошибке, ничего не возвращая —
    // частично сгенерированный набор никому не нужен.
    func generateLinkBatch(count: Int) async -> [String]? {
        guard let token = vkAuthToken else {
            showVKWebFallback = true
            return nil
        }
        creatingCall = true
        defer { creatingCall = false }
        var created: [String] = []
        for _ in 0..<max(1, count) {
            do {
                created.append(try await vkCreateCall(token: token, session: session))
            } catch {
                // Сбрасываем токен только когда VK сам сказал, что он невалиден
                // (error_code 5 — User authorization failed). Сетевые сбои и
                // прочее не должны стирать сохранённый в Keychain токен.
                if case VKCallError.apiError(5, _) = error {
                    vkAuthToken = nil
                    showVKWebFallback = true  // токен протух — сразу открываем логин
                    return nil
                }
                errorText = error.localizedDescription
                return nil
            }
        }
        return created
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
