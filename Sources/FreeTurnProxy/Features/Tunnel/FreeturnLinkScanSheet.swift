import SwiftUI

// Сканер QR под freeturn://-ссылки — отдельный от сканера WG-конфига на
// экране деталей туннеля (тот принимает только [Interface]/[Peer]).
struct FreeturnLinkScanSheet: View {
    let onImport: (SavedConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRScanner()
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cameraSection
                stateHint
                Spacer()
            }
            .navigationTitle("Сканировать QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { scanner.start() }
            .onDisappear { scanner.stop() }
            .onChange(of: scanner.scannedCode) { code in
                guard let code else { return }
                do {
                    let cfg = try FreeturnLink.parse(code, defaultName: "Импортировано по QR")
                    onImport(cfg)
                    dismiss()
                } catch {
                    errorText = error.localizedDescription
                    scanner.scannedCode = nil // разрешаем повторную попытку без пересоздания сессии
                }
            }
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
        } else if scanner.cameraAccessDenied {
            Label("Разрешите доступ к камере в Настройках", systemImage: "gearshape")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Наведите камеру на QR-код")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
