import XCTest

final class LanguageSwitchTests: XCTestCase {
    func testSwitchLanguageAndKeepChoiceAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 15))
        screenshot("dashboard-initial")

        app.buttons["settingsButton"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Today"].exists)
        screenshot("dashboard-english")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["日本語"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        screenshot("settings-japanese")
        app.buttons["完了"].tap()
        XCTAssertTrue(app.staticTexts["今日"].firstMatch.exists)
        screenshot("dashboard-japanese")

        app.buttons["settingsButton"].tap()
        app.buttons["languagePicker"].tap()
        app.buttons["Tiếng Việt"].tap()
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        app.buttons["Xong"].tap()
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
