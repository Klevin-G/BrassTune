import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPracticeAndSettingsSurfaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_DEMO", "UITEST_RESET_STATE"]
        app.launch()

        openTab("Practice", in: app)
        let recordButton = app.buttons["practice.recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Practice recording control should be visible")
        let recordingState = app.staticTexts["practice.recordingState"]
        XCTAssertTrue(recordingState.waitForExistence(timeout: 5), "Recording state should be visible")
        recordButton.tap()
        waitForElementLabel(recordingState, containing: "Recording")
        recordButton.tap()
        waitForElementLabel(recordingState, containing: "Ready")

        openTab("Sessions", in: app)
        XCTAssertTrue(app.staticTexts["Demo take"].waitForExistence(timeout: 5), "Stopping a fixture recording should create a saved session")

        openTab("Settings", in: app)
        let deleteButton = app.descendants(matching: .any)["settings.deleteAccount"]
        XCTAssertTrue(waitForElementOrScroll(deleteButton, in: app), "Account deletion control should be available in Settings")
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let directTab = app.tabBars.buttons[title]
        if directTab.waitForExistence(timeout: 5), directTab.isHittable {
            directTab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5), "\(title) should be reachable directly or from More", file: file, line: line)
        moreTab.tap()

        let candidates = [
            app.cells.containing(.staticText, identifier: title).element,
            app.buttons[title],
            app.staticTexts[title],
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 3), candidate.isHittable {
                candidate.tap()
                return
            }
        }

        XCTFail("\(title) should be listed under More on compact tab bars", file: file, line: line)
    }

    @MainActor
    private func waitForElementLabel(_ element: XCUIElement, containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "Element label should contain \(text)", file: file, line: line)
    }

    @MainActor
    private func waitForElementOrScroll(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return true
            }
            app.swipeUp()
        }
        return element.exists
    }
}
