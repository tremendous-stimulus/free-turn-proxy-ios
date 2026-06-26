import SwiftUI
import PhotosUI

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var inputError: String?
    @Published var tunnelName = ""
    @Published var showNaming = false
    @Published var selectedScheme: AllowedIPsBuilder.Scheme = .withoutWhitelist

    // Готовый .conf и переход на экран экспорта (внутри того же sheet).
    @Published var exportURL: URL?
    @Published var showExport = false

    private var pendingConfig: String?

    // Шаг 1: валидируем сырой конфиг и показываем экран ввода названия.
    // Сам сканер ставит на паузу View (по showNaming) — здесь только данные.
    func stage(rawConfig text: String, defaultName: String) {
        guard text.contains("[Interface]"), text.contains("[Peer]") else {
            inputError = "Не похоже на WireGuard/AWG конфиг"
            return
        }
        inputError = nil
        resetExport()
        pendingConfig = text
        tunnelName = defaultName
        showNaming = true
    }

    // Шаг 2: по «Продолжить» патчим, пишем .conf и переходим на экран экспорта.
    // Колбэк возвращает ошибку (или nil при успехе) обратно на шаг ввода имени.
    // Тяжёлую часть (фетч списка, патч ~36k префиксов, запись ~1МБ) держим
    // вне main через Task.detached, чтобы не фризить UI.
    func generate(_ completion: @escaping (String?) -> Void) {
        guard let text = pendingConfig else { completion("Конфиг потерян"); return }
        let safeName = tunnelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined()
        let fileName = (safeName.isEmpty ? "tunnel" : safeName) + ".conf"
        let endpoint = AppSettings.listen
        let scheme = selectedScheme

        Task.detached {
            do {
                let allowedIPs = try await AllowedIPsBuilder.build(scheme: scheme)
                let patched = ConfigPatcher.patch(text, allowedIPs: allowedIPs, endpoint: endpoint)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try patched.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.exportURL = url
                    self.showExport = true
                    completion(nil)
                }
            } catch {
                await MainActor.run { completion(error.localizedDescription) }
            }
        }
    }

    func closeSheet() {
        showNaming = false
    }

    func resetExport() {
        exportURL = nil
        showExport = false
        pendingConfig = nil
    }

    func processPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let ciImage = CIImage(image: uiImage) else {
            inputError = "Не удалось загрузить изображение"
            return
        }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let code = (detector?.features(in: ciImage) as? [CIQRCodeFeature])?.first?.messageString
        guard let code else { inputError = "QR-код не найден на фото"; return }
        stage(rawConfig: code, defaultName: ConfigStore.shared.selected?.name ?? "tunnel")
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let name = url.deletingPathExtension().lastPathComponent
                stage(rawConfig: text, defaultName: name)
            } catch {
                inputError = error.localizedDescription
            }
        case .failure(let error):
            inputError = error.localizedDescription
        }
    }
}
