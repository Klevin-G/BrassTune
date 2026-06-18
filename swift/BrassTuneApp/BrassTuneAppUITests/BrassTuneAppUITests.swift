import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPracticeAndSettingsSurfaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DEMO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Practice"].waitForExistence(timeout: 5), "Practice tab should be visible after UITEST_DEMO launch")
        app.tabBars.buttons["Practice"].tap()
        XCTAssertTrue(app.buttons["practice.recordButton"].waitForExistence(timeout: 5), "Practice recording control should be visible")
        app.buttons["practice.recordButton"].tap()
        app.buttons["practice.recordButton"].tap()
        app.tabBars.buttons["Sessions"].tap()
        XCTAssertTrue(app.staticTexts["Demo take"].waitForExistence(timeout: 5), "Stopping a fixture recording should create a saved session")
        app.terminate()
        app.launchArguments = ["UITEST_SETTINGS"]
        app.launch()
        let deleteButton = app.buttons["settings.deleteAccount"]
        var attempts = 0
        while !deleteButton.exists && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Account deletion control should be available in Settings")
    }
}
