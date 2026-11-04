import XCTest

final class NookUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsTheMainCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        launch(app)
        XCTAssertTrue(app.scrollViews["screen.home"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["home.upcoming"].exists)
        XCTAssertTrue(app.buttons["home.recentNote"].exists)
        let assistant = app.buttons["tab.assistant"]
        XCTAssertTrue(assistant.exists)
        XCTAssertEqual(assistant.frame.midX, app.frame.midX, accuracy: 2)
    }

    @MainActor
    func testEveryTabOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        launch(app)
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
        launch(app)
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
        launch(app)
        XCTAssertTrue(app.buttons["home.assistant"].waitForExistence(timeout: 15))
        capture(app, "首页-中文")
        app.buttons["tab.assistant"].tap()
        XCTAssertTrue(app.navigationBars["Nook 事务助手"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["想处理什么事情？"].exists)
        capture(app, "事务助手-中文")
        app.buttons["assistant.settings"].tap()
        XCTAssertTrue(app.textFields["模型 ID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["获取模型列表"].exists)
        XCTAssertTrue(app.buttons["ai.testConnection"].exists)
        XCTAssertFalse(app.buttons["ai.testConnection"].isEnabled)
        capture(app, "AI设置-中文")
    }

    @MainActor
    func testTasksCanBeCreatedAndEdited() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        launch(app)
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
    func testCalendarRepeatsWithoutTransportFields() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        launch(app)
        XCTAssertTrue(app.buttons["tab.schedule"].waitForExistence(timeout: 15))
        app.buttons["tab.schedule"].tap()
        let schedule = app.scrollViews["screen.schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.buttons["button.add"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Event"].waitForExistence(timeout: 5))
        enable(app.switches["Repeats"], in: app)
        reveal(app.buttons["Weekdays"], in: app)
        app.buttons["Weekdays"].tap()
        XCTAssertFalse(app.switches["Transport Details"].exists)
        capture(app, "重复日程-英文")
    }

    @MainActor
    func testTripsOwnTransportAndKeepItAfterSaving() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        launch(app)
        app.buttons["tab.schedule"].tap()
        app.buttons["Trips"].tap()
        app.scrollViews["screen.schedule"].buttons["button.add"].firstMatch.tap()
        let title = app.textFields["trip.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Hangzhou by train")
        app.navigationBars["New Trip"].tap()
        enable(app.switches["trip.transport"], in: app)
        reveal(app.textFields["Train Number"], in: app)
        app.textFields["Train Number"].tap(); app.textFields["Train Number"].typeText("G123")
        app.navigationBars["New Trip"].tap()
        reveal(app.textFields["Departure Station"], in: app)
        app.textFields["Departure Station"].tap(); app.textFields["Departure Station"].typeText("Shanghai Hongqiao")
        app.navigationBars["New Trip"].tap()
        capture(app, "行程交通-英文")
        app.buttons["trip.save"].tap()
        XCTAssertTrue(app.buttons["trip.save"].waitForNonExistence(timeout: 5))
        let saved = app.buttons["Hangzhou by train"].firstMatch
        reveal(saved, in: app); saved.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Hangzhou by train")
        reveal(app.textFields["Train Number"], in: app)
        XCTAssertEqual(app.textFields["Train Number"].value as? String, "G123")
    }

    @MainActor
    func testEnglishSettingsAndWidgetPreviewsRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appearance", "light"]
        launch(app)
        capture(app, "Home-English")
        app.buttons["home.settings"].tap()
        reveal(app.buttons["settings.language"], in: app)
        capture(app, "Language-English")
        let preview = app.buttons["Widget Previews"]
        reveal(preview, in: app); preview.tap()
        XCTAssertTrue(app.navigationBars["Widget Previews"].waitForExistence(timeout: 5))
        enable(app.switches["Show Details in Widgets"], in: app)
        capture(app, "Widget-Previews-English")
        reveal(app.staticTexts["Anniversary"], in: app)
        capture(app, "Widget-Notes-Anniversary-English")
    }

    @MainActor
    func testBackupAndMigrationSettingsRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "dark"]
        launch(app)
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

    @MainActor private func launch(_ app: XCUIApplication) {
        app.launch()
        // Demo fixtures include reminders. Handle the real first-use system prompt
        // before inspecting the app, so it cannot obscure the home screenshot.
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            for label in ["Allow", "允许"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); break }
            }
        }
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let top = app.frame.minY + 160
            let keyboard = app.keyboards.firstMatch
            let bottom = min(app.frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : app.frame.maxY)
            // SwiftUI can report a clipped row as hittable. Keep the whole row
            // inside the content area and start drags above any visible keyboard.
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            let above = element.exists && element.frame.midY < top
            let upper = top + (bottom - top) * 0.25
            let lower = top + (bottom - top) * 0.75
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: above ? upper : lower))
            let end = origin.withOffset(CGVector(dx: app.frame.width / 2, dy: above ? lower : upper))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element)")
    }

    @MainActor private func enable(_ toggle: XCUIElement, in app: XCUIApplication) {
        reveal(toggle, in: app)
        // SwiftUI exposes the entire labelled row as a Switch. Its center is the
        // label, while the actual UISwitch is at the trailing edge of that row.
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
