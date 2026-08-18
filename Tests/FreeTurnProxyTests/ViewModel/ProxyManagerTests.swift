import XCTest
@testable import FreeTurnProxy

@MainActor
final class ProxyManagerTests: XCTestCase {

    // reachabilityProbe по умолчанию — «всегда достижимо»: без этого любой
    // авто-ретрай (ступени 0–1 лестницы, план фаза 2.3) бил бы в реальную
    // сеть через 3с cheap-step follow-up. Тесты, которым нужен провал
    // (эскалация лестницы), передают свой замыкание.
    private func manager(
        reachabilityProbe: @escaping (@escaping (Bool) -> Void) -> Void = { $0(true) },
        networkPath: NetworkPathProviding = MockNetworkPath()
    ) -> (ProxyManager, MockMobileAPI) {
        let mock = MockMobileAPI()
        return (ProxyManager(mobile: mock, networkPath: networkPath, reachabilityProbe: reachabilityProbe), mock)
    }

    // ProxyManager зовёт ftun с отдельной очереди (cgo блокирующий, с главного
    // потока он вешал UI) — тест владеет этой очередью, чтобы дождаться вызова.
    private let ftunQueue = DispatchQueue(label: "tests.ftun")

    private func drainFtun() {
        ftunQueue.sync {}
    }

    private func managerWithFtun() -> (ProxyManager, MockMobileAPI, MockFtunAPI, InMemoryLocalWGConfigStore, InMemoryExternalWGConfigStore) {
        let mobile = MockMobileAPI()
        let ftun = MockFtunAPI()
        let localStore = InMemoryLocalWGConfigStore()
        let externalStore = InMemoryExternalWGConfigStore()
        return (ProxyManager(mobile: mobile, ftun: ftun, localWGConfig: localStore, externalWGConfig: externalStore,
                             ftunQueue: ftunQueue, networkPath: MockNetworkPath(), reachabilityProbe: { $0(true) }),
                mobile, ftun, localStore, externalStore)
    }

    private func sampleConfig() -> FreeTurnConfig {
        FreeTurnConfig(
            config: SavedConfig(name: "test", peer: "1.2.3.4:12345", dns: "8.8.8.8", listen: "127.0.0.1:9000"),
            links: ["https://vk.com/call/join/abc"]
        )
    }

    private func sampleLocalWGConfig() -> LocalWGConfig {
        LocalWGConfig(
            name: "freeturn-test", port: 9001,
            serverPrivateKey: "sPriv", serverPublicKey: "sPub",
            clientPrivateKey: "cPriv", clientPublicKey: "cPub", createdAt: Date()
        )
    }

    private func sampleExternalWGConfig() -> ExternalWGConfig {
        ExternalWGConfig(
            remoteConfText: "conf", address: "10.0.0.2/32", dns: "10.0.0.1",
            remoteEndpoint: "1.2.3.4:51820", createdAt: Date(), sentAt: nil
        )
    }

    // MARK: – start

    func test_start_noConfig_throwsNoConfig() {
        let (pm, _) = manager()
        XCTAssertThrowsError(try pm.start()) { err in
            XCTAssertEqual((err as? AppError), .noConfig)
        }
    }

    func test_start_withConfig_setsIsRunning() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertTrue(pm.isRunning)
        XCTAssertTrue(mock.startCalled)
        pm.stop()
    }

    // Апстрим читает protect в момент dial, поэтому сокеты, открытые до
    // установки, останутся в туннеле — порядок вызовов тут и есть суть фикса
    // петли (план, фаза 5.1).
    func test_start_setsProtectBeforeStart() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertTrue(mock.protectSetBeforeStart)
        pm.stop()
    }

    func test_stop_clearsProtect() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.stop()
        XCTAssertNil(mock.protectorSet)
    }

    func test_start_propagatesMobileError() {
        let (pm, mock) = manager()
        mock.startError = NSError(domain: "test", code: 99)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        XCTAssertThrowsError(try pm.start())
        XCTAssertFalse(pm.isRunning)
        pm.stop()
    }

    func test_start_sendsNonEmptyClientId() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        let data = Data((mock.lastConfigJSON ?? "").utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse((json["clientId"] as? String ?? "").isEmpty)
        pm.stop()
    }

    // MARK: – stop

    func test_stop_resetsFlags() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.stop()
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.connectedStreams, 0)
        XCTAssertEqual(pm.totalStreams, 0)
        XCTAssertTrue(mock.stopCalled)
    }

    // MARK: – Авто-реконнект
    //
    // Состояние теперь push-driven (EventSinkBridge.onState → ProxyManager.
    // handleState), поэтому тесты дёргают handleState напрямую вместо того,
    // чтобы выставлять mock.currentState и ждать поллинг-таймер.

    func test_autoReconnect_connectedThenError_entersRetryBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        XCTAssertEqual(mock.startCallCount, 1)

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        XCTAssertEqual(pm.state, .connected)

        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")

        XCTAssertEqual(pm.state, .retryBackoff)
        XCTAssertTrue(pm.isRunning, "isRunning должен оставаться true, чтобы UI показывал кнопку «Отключиться»")
        XCTAssertGreaterThan(pm.retryBackoffSeconds, 0, "Первый бекофф ~1с")
        XCTAssertLessThanOrEqual(pm.retryBackoffSeconds, 1)
        pm.stop()
    }

    func test_autoReconnect_connectingThenError_doesNotRetry() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        // connected мы НЕ увидели → everConnected остаётся false.
        pm.handleState("connecting", streams: 0, total: 1, errMsg: "")
        XCTAssertEqual(pm.state, .connecting)

        let startsBefore = mock.startCallCount
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertFalse(pm.isRunning)
        XCTAssertEqual(mock.startCallCount, startsBefore, "Не должно быть авто-ретраев без предыдущего connected")
        XCTAssertNotEqual(pm.state, .retryBackoff)
        pm.stop()
    }

    func test_autoReconnect_stop_cancelsBackoff() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        let restartsBefore = mock.restartCallCount
        pm.stop()

        // Ждём дольше первого бекоффа — никакого рестарта случиться не должно.
        try? await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(mock.restartCallCount, restartsBefore, "Stop должен отменить цепочку ретраев")
        XCTAssertEqual(pm.state, .idle)
        XCTAssertEqual(pm.retryBackoffSeconds, 0)
    }

    // Лестница восстановления (план, фаза 2.3): первая попытка — мягкий
    // wake(), не restartMobile — без WG-in-WG (ftunStarted == false в этих
    // тестах) nudge падает на wake автоматически. restartMobile — только
    // ступень 2, когда дешёвые ступени не привели к восстановлению
    // (reachabilityProbe стабильно возвращает false).
    func test_autoReconnect_firstAttempt_performsWake_notRestart() async throws {
        let (pm, mock) = manager(reachabilityProbe: { $0(false) })
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        let restartsBefore = mock.restartCallCount

        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline, mock.wakeCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(mock.wakeCallCount, 0, "Первая ступень лестницы — mobile.wake(), не restart")
        XCTAssertEqual(mock.restartCallCount, restartsBefore, "restartMobile не должен вызываться на первой ступени")
        pm.stop()
    }

    // Ступени 0–1 не пересоздают сессию — если reachabilityProbe стабильно
    // говорит «не восстановилось», лестница обязана эскалировать до
    // restartMobile (ступень 2), а не крутиться на wake() вечно.
    func test_autoReconnect_escalatesToRestart_whenCheapStepsDontRecover() async throws {
        let (pm, mock) = manager(reachabilityProbe: { $0(false) })
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        let restartsBefore = mock.restartCallCount

        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")

        let deadline = Date().addingTimeInterval(25.0)
        while Date() < deadline, mock.restartCallCount == restartsBefore {
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThan(mock.restartCallCount, restartsBefore,
                             "После неудачных дешёвых ступеней должен быть выполнен restartMobile")
        pm.stop()
    }

    func test_autoReconnect_recovered_returnsToConnected() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        // Полный цикл: connected → error → бекофф → опять connected (пуш от
        // ядра после того, как реконнект в фоне отработал).
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        XCTAssertEqual(pm.state, .connected)
        XCTAssertTrue(pm.isRunning)
        pm.stop()
    }

    // План, фаза 2.4: бюджет попыток убран целиком — туннель не должен
    // гаситься независимо от того, сколько раз подряд пришёл error.
    func test_autoReconnect_neverGivesUp() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        for _ in 1...8 {
            pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
            XCTAssertNotEqual(pm.state, .error, "реконнект не должен сдаваться и переходить в .error")
            XCTAssertTrue(pm.isRunning)
        }
        XCTAssertFalse(mock.stopCalled, "stop() не должен вызываться из-за исчерпанного бюджета — бюджета больше нет")
        pm.stop()
    }

    func test_autoReconnect_successResetsAttemptBudget() throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        for _ in 1...3 {
            pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        }
        XCTAssertEqual(pm.state, .retryBackoff)

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        // После успешного реконнекта лестница обязана начаться заново со
        // ступени 0 — бекофф снова ~1с, а не продолжает расти с прошлого эпизода.
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)
        XCTAssertLessThanOrEqual(pm.retryBackoffSeconds, 1)

        for _ in 1...5 {
            pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
            XCTAssertEqual(pm.state, .retryBackoff, "Бюджет попыток должен был обнулиться на connected")
            XCTAssertTrue(pm.isRunning)
        }
        pm.stop()
    }

    // У ядра свой watchdog, и оно умеет починиться само, пока мы отсиживаем
    // бекофф. handleState(connected) закрывает эпизод, но запланированный
    // work item живёт дальше — без гарда по inRetryCycle он срабатывал уже
    // поверх здоровой сессии и ронял рабочий туннель на ровном месте.
    func test_autoReconnect_pendingStep_doesNotFireAfterSelfRecovery() async throws {
        let (pm, mock) = manager()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        XCTAssertEqual(pm.state, .retryBackoff)

        // Ядро починилось само, не дожидаясь нашей ступени (бекофф ~1с).
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        let restartsBefore = mock.restartCallCount
        let wakesBefore = mock.wakeCallCount

        try? await Task.sleep(for: .milliseconds(1800))

        XCTAssertEqual(mock.wakeCallCount, wakesBefore,
                       "протухшая ступень не должна будить здоровую сессию")
        XCTAssertEqual(mock.restartCallCount, restartsBefore,
                       "протухшая ступень не должна перезапускать здоровую сессию")
        XCTAssertEqual(pm.state, .connected, "состояние не должно уехать в .connecting")
        pm.stop()
    }

    // MARK: – Смена сети (план, фаза 2.1/2.2/2.4)

    // Сокеты ядра привязаны IP_BOUND_IF к конкретному индексу интерфейса —
    // после LTE↔Wi-Fi они мертвы навсегда, ждать зонда ~5с незачем: реконнект
    // обязан случиться немедленно, без бекоффа.
    func test_networkPath_interfaceChange_triggersImmediateReconnect() throws {
        let netPath = MockNetworkPath()
        let (pm, mock) = manager(networkPath: netPath)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        let restartsBefore = mock.restartCallCount
        netPath.simulate(NetworkPathSnapshot(isSatisfied: true, interfaceIndex: 2))

        XCTAssertGreaterThan(mock.restartCallCount, restartsBefore,
                             "Смена физического интерфейса форсирует restartMobile немедленно, без бекоффа")
        XCTAssertEqual(pm.retryBackoffSeconds, 0)
        pm.stop()
    }

    // Путь обновился, но физический интерфейс тот же — не повод дёргать
    // реконнект (NWPathMonitor шлёт колбэк не только на смену интерфейса).
    func test_networkPath_sameInterface_doesNotTriggerReconnect() throws {
        let netPath = MockNetworkPath()
        let (pm, mock) = manager(networkPath: netPath)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        let restartsBefore = mock.restartCallCount
        netPath.simulate(NetworkPathSnapshot(isSatisfied: true, interfaceIndex: 1))

        XCTAssertEqual(mock.restartCallCount, restartsBefore)
        XCTAssertEqual(pm.state, .connected)
        pm.stop()
    }

    // Путь unsatisfied во время активной сессии — не жжём попытки, ждём
    // молча. Появление пути — немедленный реконнект без бекоффа.
    func test_networkPath_unsatisfied_entersWaitingNetwork_withoutBurningAttempts() throws {
        let netPath = MockNetworkPath()
        let (pm, mock) = manager(networkPath: netPath)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        netPath.simulate(NetworkPathSnapshot(isSatisfied: false, interfaceIndex: 1))
        XCTAssertEqual(pm.state, .waitingNetwork)
        XCTAssertEqual(pm.retryBackoffSeconds, 0)

        let restartsBefore = mock.restartCallCount
        let wakesBefore = mock.wakeCallCount
        netPath.simulate(NetworkPathSnapshot(isSatisfied: true, interfaceIndex: 1))

        // Реконнект пошёл немедленно (ступень 0/1 — wake, т.к. WG-in-WG тут не
        // поднят) — попытки не потрачены впустую на ожидание сети как таковой.
        XCTAssertTrue(mock.wakeCallCount > wakesBefore || mock.restartCallCount > restartsBefore)
        pm.stop()
    }

    // Wi-Fi → (путь пропал) → LTE. У unsatisfied-пути физического интерфейса
    // нет, physicalIndex отдаёт 0 — и если запомнить этот ноль, то возврат сети
    // на другом интерфейсе перестаёт выглядеть сменой интерфейса. А сокеты ядра
    // при этом так же мертвы (IP_BOUND_IF на старый индекс), и дешёвые ступени
    // их не чинят: лестница обязана начаться сразу с restartMobile.
    func test_networkPath_interfaceChangedWhileWaiting_escalatesToRestart() throws {
        let netPath = MockNetworkPath()
        let (pm, mock) = manager(networkPath: netPath)
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        netPath.simulate(NetworkPathSnapshot(isSatisfied: false, interfaceIndex: 0))
        XCTAssertEqual(pm.state, .waitingNetwork)

        let restartsBefore = mock.restartCallCount
        let wakesBefore = mock.wakeCallCount
        netPath.simulate(NetworkPathSnapshot(isSatisfied: true, interfaceIndex: 2))

        XCTAssertGreaterThan(mock.restartCallCount, restartsBefore,
                             "сеть вернулась на другом интерфейсе — сразу ступень 2")
        XCTAssertEqual(mock.wakeCallCount, wakesBefore,
                       "дешёвые ступени не трогают protect-привязку сокетов и тут бесполезны")
        pm.stop()
    }

    // MARK: – WG-in-WG (план, фаза 2)

    func test_localTunnel_startsAfterFirstConnected() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()

        drainFtun()
        XCTAssertFalse(ftun.startCalled, "ftun не должен стартовать до первого connected")
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        drainFtun()
        XCTAssertTrue(ftun.startCalled)
        XCTAssertEqual(ftun.startCallCount, 1)
        pm.stop()
    }

    func test_localTunnel_notStarted_whenUseLocalTunnelFalse() throws {
        let (pm, _, ftun, _, _) = managerWithFtun()
        pm.loadConfig(sampleConfig(), fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        drainFtun()
        XCTAssertFalse(ftun.startCalled)
        pm.stop()
    }

    func test_localTunnel_startsOnceAcrossReconnects() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()

        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        pm.handleState("error", streams: 0, total: 1, errMsg: "boom")
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        drainFtun()
        XCTAssertEqual(ftun.startCallCount, 1, "ftun не перезапускается реконнектом внешней половины")
        pm.stop()
    }

    func test_localTunnel_stoppedOnStop() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        pm.stop()
        drainFtun()
        XCTAssertEqual(ftun.stopCallCount, 1)
    }

    func test_localTunnel_missingConfig_doesNotCrashOrStartFtun() throws {
        let (pm, _, ftun, _, _) = managerWithFtun()
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true   // ни локальный, ни внешний конфиг в сторе не заведены
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        drainFtun()
        XCTAssertFalse(ftun.startCalled)
        pm.stop()
    }

    func test_localTunnel_missingExternalConfig_doesNotCrashOrStartFtun() throws {
        let (pm, _, ftun, localStore, _) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true   // общий локальный конфиг есть, а внешний для этого профиля — нет
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")
        drainFtun()
        XCTAssertFalse(ftun.startCalled)
        pm.stop()
    }

    func test_localTunnel_startSendsExpectedFields() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        drainFtun()
        let data = Data((ftun.lastConfigJSON ?? "").utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["remoteConf"] as? String, "conf")
        XCTAssertEqual(json["localPrivateKey"] as? String, "sPriv")
        XCTAssertEqual(json["localPeerPublicKey"] as? String, "cPub")
        // Тунель (апстрим-релей) — SavedConfig.listen, дефолт 127.0.0.1:9000;
        // локальный WG-responder — порт из общего конфига, дефолт 9001 (план,
        // «порты меняются местами» относительно первоначального замысла).
        XCTAssertEqual(json["relayAddr"] as? String, "127.0.0.1:9000")
        XCTAssertEqual(json["listenPort"] as? Int, 9001)
        // Адрес и DNS внешнего конфига обязаны уехать в исключения, иначе
        // трафик к серверу и резолверу туннеля ушёл бы мимо (план, фаза 5.2).
        XCTAssertEqual(json["bypassExcludeCIDRs"] as? [String], ["10.0.0.2/32", "10.0.0.1/32"])
        pm.stop()
    }

    func test_localTunnel_relayAddr_respectsCustomListen() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        cfg.config.listen = "127.0.0.1:12345"
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        drainFtun()
        let data = Data((ftun.lastConfigJSON ?? "").utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["relayAddr"] as? String, "127.0.0.1:12345")
        pm.stop()
    }

    // Релей и responder оба на loopback: одинаковый порт означал бы
    // «address already in use» внутри ftun и туннель без интернета.
    func test_localTunnel_portCollisionWithRelay_doesNotStartFtun() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())   // порт 9001
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        cfg.config.listen = "127.0.0.1:9001"     // туннель на том же порту
        externalStore.save(sampleExternalWGConfig(), for: cfg.config.id)
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        drainFtun()
        XCTAssertFalse(ftun.startCalled)
        pm.stop()
    }

    // Разные профили держат разные внешние серверы на общей локальной
    // половине — ровно то, что просил юзер этим рефактором.
    func test_localTunnel_differentProfiles_useDifferentExternalConfigs() throws {
        let (pm, _, ftun, localStore, externalStore) = managerWithFtun()
        localStore.save(sampleLocalWGConfig())
        var cfg = sampleConfig()
        cfg.config.useLocalTunnel = true
        var otherExternal = sampleExternalWGConfig()
        otherExternal.remoteConfText = "other-conf"
        otherExternal.address = "10.9.0.2/32"
        externalStore.save(otherExternal, for: cfg.config.id)
        // Внешний конфиг какого-то другого профиля не должен быть виден.
        externalStore.save(sampleExternalWGConfig(), for: UUID())
        pm.loadConfig(cfg, fileName: "test.freeturn")
        try pm.start()
        pm.handleState("connected", streams: 1, total: 1, errMsg: "")

        drainFtun()
        let data = Data((ftun.lastConfigJSON ?? "").utf8)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["remoteConf"] as? String, "other-conf")
        XCTAssertEqual(json["bypassExcludeCIDRs"] as? [String], ["10.9.0.2/32", "10.0.0.1/32"])
        pm.stop()
    }
}
