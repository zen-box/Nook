import XCTest

final class NookUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsTheMainCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.scrollViews["screen.home"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["home.upcoming"].exists)
        XCTAssertTrue(app.buttons["home.recentNote"].exists)
    }

    @MainActor
    func testEveryTabOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
        for tab in ["notes", "vault", "schedule", "finance", "home"] {
            app.buttons["tab.\(tab)"].tap()
            XCTAssertTrue(app.scrollViews["screen.\(tab)"].waitForExistence(timeout: 5), "The \(tab) screen did not appear")
        }
    }

    @MainActor
    func testOpeningANoteHidesTheTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let recentNote = app.buttons["home.recentNote"]
        XCTAssertTrue(recentNote.waitForExistence(timeout: 15))
        recentNote.tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAssistantAndSettingsRenderInChinese() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["home.assistant"].waitForExistence(timeout: 15))
        capture(app, "首页-中文")
        app.buttons["home.assistant"].tap()
        XCTAssertTrue(app.navigationBars["Nook 事务助手"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["想处理什么事情？"].exists)
        capture(app, "事务助手-中文")
        app.buttons["assistant.settings"].tap()
        XCTAssertTrue(app.textFields["模型 ID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["获取模型列表"].exists)
        capture(app, "AI设置-中文")
    }

    @MainActor
    func testTasksCanBeCreatedAndEdited() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["home.tasks"].waitForExistence(timeout: 15))
        app.buttons["home.tasks"].tap()
        app.buttons["task.add"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Buy a train ticket")
        app.buttons["task.save"].tap()
        XCTAssertTrue(app.buttons["task.save"].waitForNonExistence(timeout: 5))
        let task = app.buttons["Buy a train ticket"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        XCTAssertEqual(title.value as? String, "Buy a train ticket")
        capture(app, "任务编辑")
    }

    @MainActor
    func testRecurringEventEditorExposesRepeatAndTransport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.schedule"].waitForExistence(timeout: 15))
        app.buttons["tab.schedule"].tap()
        let schedule = app.scrollViews["screen.schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.buttons["button.add"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 5))
        reveal(app.switches["Repeats"], in: app)
        app.switches["Repeats"].tap()
        XCTAssertTrue(app.buttons["Weekdays"].exists)
        reveal(app.switches["Transport Details"], in: app)
        app.switches["Transport Details"].tap()
        reveal(app.textFields["Train Number"], in: app)
        XCTAssertTrue(app.textFields["Departure Station"].exists)
        capture(app, "重复与交通信息")
    }

    @MainActor
    func testBackupAndMigrationSettingsRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 15))
        app.buttons["home.settings"].tap()
        let backup = app.buttons["加密备份"]
        reveal(backup, in: app); backup.tap()
        XCTAssertTrue(app.buttons["选择加密备份文件"].waitForExistence(timeout: 5))
        capture(app, "加密备份-深色")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let migration = app.buttons["设备迁移"]
        reveal(migration, in: app); migration.tap()
        XCTAssertTrue(app.buttons["新手机：接收数据"].waitForExistence(timeout: 5))
        capture(app, "设备迁移-深色")
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
