import XCTest

final class LanguageSwitchTests: XCTestCase {
    func testSwitchLanguageAndKeepChoiceAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-settings"].waitForExistence(timeout: 15))
        screenshot("dashboard-initial")

        app.buttons["tab-settings"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.staticTexts["Today"].exists)
        screenshot("dashboard-english")
        app.buttons["tab-statistics"].tap()
        XCTAssertTrue(app.staticTexts["periodTotal"].waitForExistence(timeout: 5))
        screenshot("statistics-month")
        app.segmentedControls.buttons["Year"].tap()
        for month in 1...12 { XCTAssertTrue(app.buttons["month-\(month)"].exists) }
        screenshot("statistics-year")
        app.buttons["month-1"].tap()
        XCTAssertTrue(app.buttons["day-\(Calendar.current.component(.year, from: Date()))-01-01"].exists)
        app.buttons["tab-home"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))
        app.buttons["tab-settings"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["日本語"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        screenshot("settings-japanese")
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.staticTexts["今日"].firstMatch.exists)
        screenshot("dashboard-japanese")

        app.buttons["tab-settings"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.staticTexts["Hôm nay"].exists)
        screenshot("dashboard-vietnamese")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
