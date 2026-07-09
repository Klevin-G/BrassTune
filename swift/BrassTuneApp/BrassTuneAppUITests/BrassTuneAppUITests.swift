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

        let startPracticeButton = app.descendants(matching: .any)["home.startPractice"]
        XCTAssertTrue(waitForElementOrScroll(startPracticeButton, in: app), "Home should expose a practice entry point")
        startPracticeButton.tap()

        let recordButton = app.buttons["practice.recordButton"]
        if !recordButton.waitForExistence(timeout: 3) {
            openTab("Practice", in: app)
        }
        guard let startRecordButton = firstAvailableElement(
            [
                app.descendants(matching: .any)["practice.recordButton"],
                app.buttons["Start sample take"]
            ],
            in: app,
            timeout: 10
        ) else {
            XCTFail("Practice recording control should be visible")
            return
        }
        let recordingState = app.staticTexts["practice.recordingState"]
        XCTAssertTrue(
            waitForAnyElement([recordingState, app.staticTexts["Sample ready"]], timeout: 5),
            "Recording state should be visible"
        )
        startRecordButton.tap()
        XCTAssertTrue(
            waitForAnyElement([recordingState, app.staticTexts["Sample running"]], timeout: 5),
            "Sample state should switch to running"
        )
        let floatingStop = app.descendants(matching: .any)["practice.floating.stop"]
        XCTAssertTrue(floatingStop.waitForExistence(timeout: 5), "Recording should expose floating stop control")
        let floatingMetronome = app.descendants(matching: .any)["practice.floating.metronome"]
        XCTAssertTrue(floatingMetronome.waitForExistence(timeout: 5), "Floating controls should expose metronome control")
        floatingMetronome.tap()
        floatingStop.tap()
        if !waitForAnyElement([recordingState, app.staticTexts["Sample ready"]], timeout: 5) {
            guard let stopRecordButton = firstAvailableElement(
                [
                    app.descendants(matching: .any)["practice.recordButton"],
                    app.buttons["Stop sample take"]
                ],
                in: app,
                timeout: 5
            ) else {
                XCTFail("Practice stop control should be visible")
                return
            }
            stopRecordButton.tap()
        }
        let floatingMetronomeAgain = app.descendants(matching: .any)["practice.floating.metronome"]
        if floatingMetronomeAgain.waitForExistence(timeout: 2) {
            floatingMetronomeAgain.tap()
        }
        XCTAssertTrue(
            waitForAnyElement([recordingState, app.staticTexts["Sample ready"]], timeout: 5),
            "Sample state should return to ready"
        )

        guard let metronomeShortcut = firstAvailableElement(
            [app.descendants(matching: .any)["practice.metronome"], app.buttons["Metronome"]],
            in: app,
            timeout: 5
        ) else {
            XCTFail("Practice should link to metronome")
            return
        }
        metronomeShortcut.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5), "Metronome screen should be implemented")
        XCTAssertTrue(app.descendants(matching: .any)["metronome.toggle"].waitForExistence(timeout: 5), "Metronome should expose start/stop")
        closeNavigationDetailIfPresent(in: app)

        guard let viewAnalyticsButton = firstAvailableElement(
            [
                app.descendants(matching: .any)["practice.viewAnalytics"],
                app.buttons["View analytics"]
            ],
            in: app,
            timeout: 10
        ) else {
            XCTFail("Practice should link to analytics after saving a take")
            return
        }
        viewAnalyticsButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["analytics.metrics"].waitForExistence(timeout: 5), "Analytics should derive from the local sample take")

        app.descendants(matching: .any)["analytics.reviewSessions"].tap()
        if !app.staticTexts["Sample take"].waitForExistence(timeout: 3) {
            openTab("Sessions", in: app)
        }
        let demoTake = app.staticTexts["Sample take"]
        XCTAssertTrue(demoTake.waitForExistence(timeout: 5), "Stopping a sample recording should create a saved session")
        demoTake.tap()
        let deleteSessionButton = app.descendants(matching: .any)["session.deleteButton"]
        XCTAssertTrue(waitForElementOrScroll(deleteSessionButton, in: app), "Session detail should expose a delete control")
        deleteSessionButton.tap()
        let confirmDeleteSession = app.buttons["Delete local session"]
        XCTAssertTrue(confirmDeleteSession.waitForExistence(timeout: 5), "Deleting a session should require confirmation")
        confirmDeleteSession.tap()
        XCTAssertTrue(app.staticTexts["No saved sessions"].waitForExistence(timeout: 5), "Deleting the session should remove it from the list")

        openTab("Coach", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.coach"].waitForExistence(timeout: 5), "Coach tab should expose the native coach surface")

        openTab("More", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.more"].waitForExistence(timeout: 5), "More tab should expose the native hub")

        app.descendants(matching: .any)["more.sessions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.sessions"].waitForExistence(timeout: 5), "More should link to saved sessions")
        closeNavigationDetailIfPresent(in: app)

        app.descendants(matching: .any)["more.metronome"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5), "More should link to the native metronome")
        closeNavigationDetailIfPresent(in: app)

        app.descendants(matching: .any)["more.scorepractice"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5), "More should link to native Score Practice")
        let sampleScoreButton = app.buttons["score.import.sample"]
        XCTAssertTrue(sampleScoreButton.waitForExistence(timeout: 5), "Score Practice should expose a sample import for simulator coverage")
        sampleScoreButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 5), "Sample score should create a local score card")
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["score.rotate"], in: app), "Score pages should expose rotate")
        closeNavigationDetailIfPresent(in: app)

        app.descendants(matching: .any)["more.settings"].tap()
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.deleteAccount"], in: app), "More should link to Settings")
        XCTAssertTrue(app.descendants(matching: .any)["settings.clearLocalData"].waitForExistence(timeout: 5), "Settings should expose local data clearing")

        app.terminate()
        app.launchArguments = ["UITEST_SETTINGS", "UITEST_RESET_STATE"]
        app.launch()
        let deleteButton = app.descendants(matching: .any)["settings.deleteAccount"]
        XCTAssertTrue(waitForElementOrScroll(deleteButton, in: app), "Account deletion control should be available in Settings")
    }

    @MainActor
    private func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
        }
        return elements.contains(where: { $0.exists })
    }

    @MainActor
    private func waitForElementOrScroll(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func firstAvailableElement(_ elements: [XCUIElement], in app: XCUIApplication, timeout: TimeInterval = 8) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in elements where element.exists && element.isHittable {
                return element
            }
            app.swipeUp()
        }
        return elements.first { $0.exists && $0.isHittable }
    }

    @MainActor
    private func closeNavigationDetailIfPresent(in app: XCUIApplication) {
        let backButtons = [
            app.navigationBars.buttons["BackButton"],
            app.navigationBars.buttons["Practice"],
            app.navigationBars.buttons["More"],
            app.navigationBars.buttons["Back"]
        ]
        for button in backButtons where button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[title]
        if tabButton.waitForExistence(timeout: 3) {
            tabButton.tap()
            return
        }

        let moreButton = app.tabBars.buttons["More"]
        if moreButton.waitForExistence(timeout: 3) {
            moreButton.tap()
            let overflowButton = app.buttons[title]
            XCTAssertTrue(overflowButton.waitForExistence(timeout: 5), "\(title) should be available from More", file: file, line: line)
            overflowButton.tap()
            return
        }

        XCTFail("\(title) tab should be available", file: file, line: line)
    }
}
