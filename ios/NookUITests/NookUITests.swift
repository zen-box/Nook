import XCTest

final class NookUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsTheMainCards() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.scrollViews["screen.home"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["home.upcoming"].exists)
        XCTAssertTrue(app.buttons["home.recentNote"].exists)
    }

    @MainActor
    func testEveryTabOpens() throws {
        let app = XCUIApplication()
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
        app.launch()
        let recentNote = app.buttons["home.recentNote"]
        XCTAssertTrue(recentNote.waitForExistence(timeout: 15))
        recentNote.tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 5))
    }
}
