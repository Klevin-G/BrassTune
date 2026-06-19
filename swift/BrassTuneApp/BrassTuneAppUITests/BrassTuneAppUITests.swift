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
        openSettings(in: app)
        let deleteButton = app.descendants(matching: .any)["settings.deleteAccount"]
        let deleteLabel = app.buttons["Delete account"]
        var attempts = 0
        while !deleteButton.exists && !deleteLabel.exists && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 5) || deleteLabel.waitForExistence(timeout: 1),
            "Account deletion control should be available in Settings"
        )
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5), "Settings should be reachable directly or from More")
        moreTab.tap()

        let settingsCell = app.cells.containing(.staticText, identifier: "Settings").element
        if settingsCell.waitForExistence(timeout: 5) {
            settingsCell.tap()
            return
        }

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings should be listed under More on compact tab bars")
        settingsButton.tap()
    }
}
