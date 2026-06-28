import XCTest

final class SmokeTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Пропускаем алерт "Сбор технических данных" при первом запуске.
        app.launchArguments = ["-telemetry_onboarded", "1"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: – Навигация

    func test_allFourTabsExist() {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.buttons["Туннель"].exists)
        XCTAssertTrue(bar.buttons["Конфиг VPN"].exists)
        XCTAssertTrue(bar.buttons["Логи"].exists)
        XCTAssertTrue(bar.buttons["Помощь"].exists)
    }

    // MARK: – Туннель: VK-ссылка

    // Логика валидации vkLink покрыта юнит-тестами ValidatorsTests.test_vkLink_*.
    // UI-смоук на сам TextField нестабилен из-за keyboard dismiss в XCUITest.

    // MARK: – Туннель: без конфигурации

    func test_noConfig_connectButtonAbsent() {
        // Кнопка «Подключиться» рендерится только при наличии выбранной конфигурации.
        XCTAssertFalse(app.buttons["Подключиться"].exists)
    }

    // MARK: – Туннель: меню «+»

    func test_addMenu_showsExpectedItems() {
        let addButton = app.buttons["Добавить конфигурацию"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()
        XCTAssertTrue(app.buttons["Добавить вручную"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Импортировать из файла"].exists)
    }

    // MARK: – Логи

    func test_logs_settingsButtonOpensSheet() {
        app.tabBars.firstMatch.buttons["Логи"].tap()
        // Ждём навигационный заголовок.
        let title = app.navigationBars["Логи"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        let gear = app.buttons["gearshape"]
        XCTAssertTrue(gear.waitForExistence(timeout: 3))
        gear.tap()

        // Шит настроек: ждём тумблеры.
        let toggle1 = app.switches.matching(NSPredicate(
            format: "label CONTAINS[cd] 'диагностику'")).firstMatch
        XCTAssertTrue(toggle1.waitForExistence(timeout: 3))

        let toggle2 = app.switches.matching(NSPredicate(
            format: "label CONTAINS[cd] 'между подключениями'")).firstMatch
        XCTAssertTrue(toggle2.exists)
    }

    // MARK: – Помощь

    func test_help_firstFAQQuestionVisible() {
        app.tabBars.firstMatch.buttons["Помощь"].tap()
        let first = app.staticTexts["Как работает приложение?"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
    }

    func test_help_supportButtonVisible() {
        app.tabBars.firstMatch.buttons["Помощь"].tap()
        let support = app.staticTexts["Написать в поддержку"]
        XCTAssertTrue(support.waitForExistence(timeout: 3))
    }
}
