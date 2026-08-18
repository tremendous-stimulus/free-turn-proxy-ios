import AVFoundation
import UIKit

// Удерживает процесс живым в фоне, зациклив тихий аудиоклип.
// Используется AVAudioPlayer, а НЕ AVAudioEngine: живой движок, гонящий тишину,
// не следует за сменой аудио-маршрута (Bluetooth), из-за чего сначала идут
// артефакты, а потом звук других приложений умирает до передёргивания выхода.
// AVAudioPlayer корректно переживает route change / interruption.
// Требует UIBackgroundModes: audio в Info.plist.
//
// Роли двух механизмов не путать: аудио — двигатель (пока играет, фоновое время
// не ограничено), а beginBackgroundTask — мостик на те ~30с, когда двигатель
// заглох. Восстановление здесь событийное, а не по тику таймера: усыпление
// процессное и наступает за доли секунды после того, как пропало основание для
// фона, поэтому опрос раз в секунду эту гонку почти всегда проигрывает.
final class AudioKeepAlive: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []

    // Паузы между попытками поднять звук. Одной попытки мало: сразу после
    // звонка чужое приложение ещё держит аудиофокус, и setActive штатно падает.
    // Сумма укладывается в бюджет background task.
    private static let recoveryDelays: [TimeInterval] = [0, 1, 2, 4, 8, 14]

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var recoveryWork: DispatchWorkItem?
    private var recoveryAttempt = 0

    // Идемпотентно: зовётся на каждой смене состояния туннеля, а не один раз за
    // сессию. Плеер уже есть — просто убеждаемся, что он играет.
    func start() throws {
        guard player == nil else {
            ensurePlaying()
            return
        }
        try configureAndPlay()
        registerObservers()
    }

    // Подстраховка на случай, когда состояние туннеля стоит на месте часами, а
    // звук умер от внешней причины: событийные пути ниже такое не ловят.
    func ensurePlaying() {
        guard player != nil, player?.isPlaying != true else { return }
        beginRecovery()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        cancelRecovery()
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
        player.delegate = self
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

        // Прерывание (звонок, Siri). На .began основание для фонового исполнения
        // исчезает — мостик берём сразу, пока исполнение ещё есть, иначе к
        // моменту .ended нас уже усыпят и возобновлять будет некому.
        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .ended: self.beginRecovery(restartLadder: true)
            default:     self.beginRecovery()
            }
        })

        // Смена маршрута (подключение/отключение Bluetooth) — убеждаемся, что играем.
        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.ensurePlaying()
        })

        // Сброс медиа-сервера — пересоздаём всё с нуля.
        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
            self.beginRecovery(restartLadder: true)
        })
    }

    // MARK: – AVAudioPlayerDelegate

    // При numberOfLoops = -1 штатно не приходит: если пришло — воспроизведение
    // сорвалось, и это ровно тот момент, когда исполнение ещё есть.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        beginRecovery(restartLadder: true)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        beginRecovery(restartLadder: true)
    }

    // MARK: – Восстановление

    // restartLadder — когда у попытки прямо сейчас есть шанс (прерывание
    // закончилось, медиасервер перезапустился): сбрасываем лестницу и пробуем
    // немедленно, не дожидаясь текущей паузы.
    private func beginRecovery(restartLadder: Bool = false) {
        if restartLadder {
            recoveryWork?.cancel()
            recoveryWork = nil
            recoveryAttempt = 0
        }
        guard recoveryWork == nil else { return }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "audio-keepalive") { [weak self] in
                // Не отдать токен по истечении — приложение убьют, а не усыпят.
                self?.cancelRecovery()
            }
        }
        scheduleRecoveryAttempt(after: Self.recoveryDelays[min(recoveryAttempt, Self.recoveryDelays.count - 1)])
    }

    private func scheduleRecoveryAttempt(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.attemptRecovery() }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func attemptRecovery() {
        if player?.isPlaying == true {
            finishRecovery()
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        if player?.play() != true {
            // Плеер мог осиротеть (сброс медиасервера) — пересобираем.
            try? configureAndPlay()
        }
        if player?.isPlaying == true {
            finishRecovery()
            return
        }
        recoveryAttempt += 1
        guard recoveryAttempt < Self.recoveryDelays.count else {
            // Бюджет исчерпан. Держать токен дальше нельзя — это гарантированная
            // смерть приложения вместо усыпления; поднимет уже только возврат
            // пользователя в приложение.
            cancelRecovery()
            return
        }
        scheduleRecoveryAttempt(after: Self.recoveryDelays[recoveryAttempt])
    }

    private func finishRecovery() {
        recoveryWork?.cancel()
        recoveryWork = nil
        recoveryAttempt = 0
        endBackgroundTask()
    }

    private func cancelRecovery() {
        recoveryWork?.cancel()
        recoveryWork = nil
        recoveryAttempt = 0
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: – Клип

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
