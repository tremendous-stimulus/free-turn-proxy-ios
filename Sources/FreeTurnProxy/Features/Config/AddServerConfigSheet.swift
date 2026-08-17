import SwiftUI
import PhotosUI

// Ввод реального wg/awg-конфига пользователя (карточка «Конфиг вашего
// VPN-сервера» на экране деталей туннеля): камера/галерея/файл — без шага
// именования и выбора схемы AllowedIPs, здесь только текст конфига.
struct AddServerConfigSheet: View {
    let onPicked: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRScanner()
    @Environment(\.scenePhase) private var scenePhase
    @State private var photosItem: PhotosPickerItem?
    @State private var showFilePicker = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cameraSection
                stateHint
                Spacer()
                bottomButtons.padding()
            }
            .navigationTitle("Конфиг сервера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear { if scenePhase == .active { scanner.start() } }
            .onDisappear { scanner.stop() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { scanner.start() } else { scanner.stop() }
            }
            .onChange(of: scanner.scannedCode) { code in
                guard let code else { return }
                scanner.scannedCode = nil
                handle(code)
            }
            .onChange(of: photosItem) { item in
                guard let item else { return }
                photosItem = nil
                Task { await processPhoto(item) }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data, .plainText],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
        }
    }

    private var cameraSection: some View {
        ZStack {
            if scanner.cameraAccessDenied {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemFill))
                VStack(spacing: 10) {
                    Image(systemName: "camera.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Нет доступа к камере")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                CameraPreviewView(session: scanner.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 180, height: 180)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }

    @ViewBuilder
    private var stateHint: some View {
        if let errorText {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            .padding(.horizontal)
            .padding(.top, 10)
        } else if scanner.cameraAccessDenied {
            Label("Разрешите доступ к камере в Настройках", systemImage: "gearshape")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            Text("Наведите камеру на QR-код конфигурации вашего VPN-сервера")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photosItem, matching: .images) {
                Label("Из галереи", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button { showFilePicker = true } label: {
                Label("Из файла", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func handle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("[Interface]"), trimmed.contains("[Peer]") else {
            errorText = "Не похоже на WireGuard/AWG конфиг"
            return
        }
        errorText = nil
        onPicked(trimmed)
        dismiss()
    }

    private func processPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let ciImage = CIImage(image: uiImage) else {
            errorText = "Не удалось загрузить изображение"
            return
        }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let code = (detector?.features(in: ciImage) as? [CIQRCodeFeature])?.first?.messageString
        guard let code else { errorText = "QR-код не найден на фото"; return }
        handle(code)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                handle(text)
            } catch {
                errorText = error.localizedDescription
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }
}
