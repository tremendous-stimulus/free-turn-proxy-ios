import SwiftUI
import PhotosUI

struct ConfigView: View {
    let isSelected: Bool
    @StateObject private var vm = ConfigViewModel()
    @StateObject private var scanner = QRScanner()
    @Environment(\.scenePhase) private var scenePhase
    @State private var photosItem: PhotosPickerItem?
    @State private var showFilePicker = false

    // Камера должна работать ровно когда вкладка выбрана, сцена активна и мы не
    // вводим имя. Без проверки isSelected невидимая вкладка в TabView запускала
    // камеру при возврате из фона (индикатор камеры горел на других вкладках).
    private var shouldScan: Bool {
        isSelected && scenePhase == .active && !vm.showNaming
    }

    private func syncScanner() {
        if shouldScan { scanner.start() } else { scanner.stop() }
    }

    var body: some View {
        VStack(spacing: 0) {
            cameraSection
            stateHint
            Spacer()
            bottomButtons.padding()
        }
        .navigationTitle("Конфиг VPN")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { syncScanner() }
        .onDisappear { scanner.stop() }
        // Единый драйвер камеры: реагируем на смену вкладки, фон/возврат и ввод
        // имени. Замена прежних разрозненных start/stop, из-за которых камера
        // оживала на невидимой вкладке после сворачивания приложения.
        .onChange(of: shouldScan) { _ in syncScanner() }
        .onChange(of: scanner.scannedCode) { code in
            guard let code else { return }
            scanner.scannedCode = nil
            vm.stage(rawConfig: code, defaultName: "tunnel")
        }
        .onChange(of: photosItem) { item in
            guard let item else { return }
            photosItem = nil
            Task { await vm.processPhoto(item) }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false,
            onCompletion: vm.handleImport
        )
        .sheet(isPresented: $vm.showNaming, onDismiss: { vm.resetExport() }) {
            ConfigSheet(vm: vm)
        }
    }

    // MARK: – Subviews

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
        if let msg = vm.inputError {
            hintRow(icon: "xmark.circle.fill", tint: .red, text: msg, color: .red)
        } else if scanner.cameraAccessDenied {
            Label("Разреши доступ к камере в Настройках", systemImage: "gearshape")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            Text("Наведи камеру на QR-код конфигурации")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func hintRow(icon: String, tint: Color, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote).foregroundStyle(color)
        }
        .padding(.horizontal)
        .padding(.top, 10)
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
}
