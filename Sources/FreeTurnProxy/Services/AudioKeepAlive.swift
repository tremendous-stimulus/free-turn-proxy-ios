import AVFoundation

// Удерживает процесс живым в фоне, зациклив тихий аудиоклип.
// Используется AVAudioPlayer, а НЕ AVAudioEngine: живой движок, гонящий тишину,
// не следует за сменой аудио-маршрута (Bluetooth), из-за чего сначала идут
// артефакты, а потом звук других приложений умирает до передёргивания выхода.
// AVAudioPlayer корректно переживает route change / interruption.
// Требует UIBackgroundModes: audio в Info.plist.
final class AudioKeepAlive {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []

    func start() throws {
        try configureAndPlay()
        registerObservers()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAndPlay() throws {
        let session = AVAudioSession.sharedInstance()
        // .mixWithOthers — мешаемся минимально, не прерываем и не дакаем чужой звук.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let url = try Self.silentClipURL()
        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        // Контент — цифровая тишина (нули), поэтому громкость не влияет на слышимость;
        // держим 1.0, чтобы iOS точно считал воспроизведение активным (keepalive).
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        self.player = player
    }

    private func registerObservers() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        // После прерывания (звонок, Siri) возобновляем тихий цикл.
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? session.setActive(true)
            self.player?.play()
        })

        // Смена маршрута (подключение/отключение Bluetooth) — убеждаемся, что играем.
        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let player = self?.player, !player.isPlaying else { return }
            player.play()
        })

        // Сброс медиа-сервера — пересоздаём всё с нуля.
        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.player?.stop()
            self?.player = nil
            try? self?.configureAndPlay()
        })
    }

    // Один раз генерирует крошечный тихий WAV во временной директории и возвращает URL.
    private static func silentClipURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ftp_silence.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try makeSilentWAV(seconds: 1, sampleRate: 8000).write(to: url)
        }
        return url
    }

    private static func makeSilentWAV(seconds: Int, sampleRate: Int) -> Data {
        let channels = 1, bitsPerSample = 16
        let dataSize = seconds * sampleRate * channels * bitsPerSample / 8
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var d = Data()
        func ascii(_ s: String) { d.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate))
        u16(UInt16(blockAlign)); u16(UInt16(bitsPerSample))
        ascii("data"); u32(UInt32(dataSize))
        d.append(Data(count: dataSize)) // нули = тишина
        return d
    }
}
