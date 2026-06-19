import AVFoundation
import Combine

final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?
    @Published var cameraAccessDenied = false
    let session = AVCaptureSession()
    private var isConfigured = false

    func start() {
        scannedCode = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() }
                else { DispatchQueue.main.async { self?.cameraAccessDenied = true } }
            }
        case .authorized:
            run()
        default:
            DispatchQueue.main.async { self.cameraAccessDenied = true }
        }
    }

    // Конфигурируем сессию ровно один раз; при возврате на вкладку только
    // перезапускаем running. Повторный addInput/addOutput на той же сессии
    // ронял приложение (Unsupported type org.iso.QRCode).
    private func run() {
        if !isConfigured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            output.setMetadataObjectsDelegate(self, queue: .main)
            session.commitConfiguration()
            // metadataObjectTypes валиден только после того, как output
            // добавлен и конфигурация закоммичена.
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
            isConfigured = true
        }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard scannedCode == nil,
              let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue else { return }
        scannedCode = code
    }
}
