import XCTest

final class LanguageSwitchTests: XCTestCase {
    func testNavigationBodyMapAnalyticsAndLanguagePersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--language=en", "--theme=emerald", "--appearance=light"]
        app.launch()

        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["open-settings"].exists)
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        screenshot("01-today-en")

        // Train tab (Weekly Split & Workout)
        app.buttons["tab-train"].tap()
        XCTAssertTrue(app.staticTexts["Train"].waitForExistence(timeout: 5))
        screenshot("02-train")

        // Body Map 3D & Offline Exercise Library
        app.buttons["tab-body"].tap()
        XCTAssertTrue(app.otherElements["bodyMap3DView"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["bodyFlipButton"].exists)
        XCTAssertTrue(app.buttons["bodyResetButton"].exists)
        XCTAssertTrue(app.textFields["exerciseSearchField"].exists)
        app.buttons["bodyFlipButton"].tap()
        Thread.sleep(forTimeInterval: 0.7)
        screenshot("03-bodymap-3d-back")
        app.buttons["bodyResetButton"].tap()

        // Health tab (Sleep, Meals, Calories In/Out, Hydration, Weight, Goals)
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.staticTexts["Health"].waitForExistence(timeout: 5))
        screenshot("04-health")

        // Stats tab (Week / Month / Year Dashboards)
        app.buttons["tab-stats"].tap()
        XCTAssertTrue(app.staticTexts["periodTotal"].waitForExistence(timeout: 5))
        screenshot("05-stats-month")

        let segmentedYear = app.segmentedControls["statsPeriodPicker"].buttons["Year"]
        let yearButton = segmentedYear.exists ? segmentedYear : app.buttons["Year"]
        XCTAssertTrue(yearButton.waitForExistence(timeout: 5))
        yearButton.tap()

        scrollUntilVisible(app.buttons["month-12"], in: app, maxSwipes: 6)
        for month in 1...12 {
            scrollUntilVisible(app.buttons["month-\(month)"], in: app, maxSwipes: 3)
            XCTAssertTrue(app.buttons["month-\(month)"].exists)
        }
        screenshot("06-stats-year")
        app.buttons["month-1"].tap()
        let janFirstID = "day-\(Calendar.current.component(.year, from: Date()))-01-01"
        scrollUntilVisible(app.buttons[janFirstID], in: app)
        XCTAssertTrue(app.buttons[janFirstID].exists)

        // Open Settings & verify language switch persists across relaunch
        app.buttons["tab-today"].tap()
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["languagePicker"].exists)
        XCTAssertTrue(app.buttons["themePicker"].exists)
        screenshot("07-settings")

        app.buttons["languagePicker"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        let doneVi = app.buttons["Xong"]
        if doneVi.exists { doneVi.tap() } else { app.navigationBars["Cài đặt"].buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["Hôm nay"].waitForExistence(timeout: 5))
        screenshot("08-today-vi")

        // Relaunch without --language override to verify persisted Vietnamese choice
        app.terminate()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hôm nay"].waitForExistence(timeout: 10))

        // Switch to Japanese & back to English
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        app.buttons["languagePicker"].tap()
        app.buttons["日本語"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        let doneJa = app.buttons["完了"]
        if doneJa.exists { doneJa.tap() } else { app.navigationBars["設定"].buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["今日"].firstMatch.waitForExistence(timeout: 5))
        screenshot("09-today-ja")

        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.buttons["languagePicker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let doneEn = app.buttons["Done"]
        if doneEn.exists { doneEn.tap() } else { app.navigationBars["Settings"].buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 5) {
        var count = 0
        while !element.exists && count < maxSwipes {
            app.swipeUp()
            count += 1
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
