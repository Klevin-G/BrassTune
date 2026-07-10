import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingOnlyAsksForInstrumentAndStart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.hero"].waitForExistence(timeout: 8),
            "Onboarding should open for a normal first launch"
        )
        XCTAssertTrue(app.staticTexts["Choose your instrument"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.instrumentPicker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.startPractice"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["settings.referencePitchStepper"].exists)
        XCTAssertFalse(app.staticTexts["How BrassTune records"].exists)
        XCTAssertFalse(app.staticTexts["No lock means confidence is too low to save. Unstable pitch means lock exists but cents vary too much."].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "physical-device")).count,
            0
        )

        app.descendants(matching: .any)["onboarding.startPractice"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.playAlong"].waitForExistence(timeout: 5),
            "Start should lead to the flagship Play-Along tab"
        )
    }

    @MainActor
    func testLaunchPracticeAndSettingsSurfaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        assertFourTabInformationArchitecture(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.playAlong"].waitForExistence(timeout: 8),
            "Play-Along should be the first tab"
        )
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.exercisePicker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.exerciseNotes"].exists)

        let playAlongStart = app.descendants(matching: .any)["playAlong.start"]
        XCTAssertTrue(playAlongStart.waitForExistence(timeout: 5))
        playAlongStart.tap()

        let targetNote = app.descendants(matching: .any)["playAlong.targetNote"]
        let score = app.descendants(matching: .any)["playAlong.score"]
        XCTAssertTrue(
            waitForAnyElement([targetNote, score], timeout: 3),
            "UITEST_FIXTURES should drive the same Play-Along grader without exposing a source picker"
        )
        XCTAssertTrue(score.waitForExistence(timeout: 8), "The deterministic exercise should complete")
        XCTAssertTrue(score.label.contains("100"), "Centered fixture notes should receive a real 100% grader result")
        XCTAssertFalse(app.descendants(matching: .any)["practice.recordingSource"].exists)
        XCTAssertFalse(app.buttons["Sample"].exists)
        XCTAssertFalse(app.buttons["Live mic"].exists)

        openTab("Tuner", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["tuner.note"].label, "Play a note")
        XCTAssertEqual(app.descendants(matching: .any)["tuner.verdict"].label, "Listening…")
        XCTAssertFalse(app.descendants(matching: .any)["practice.recordingSource"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["practice.microphonePermission"].exists)
        XCTAssertFalse(app.buttons["Request microphone permission"].exists)

        let tunerStart = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(tunerStart.waitForExistence(timeout: 5))
        tunerStart.tap()

        let floatingBar = app.descendants(matching: .any)["tuner.floatingBar"]
        XCTAssertTrue(floatingBar.waitForExistence(timeout: 5), "Recording should expose the floating practice transport")
        let floatingMetronome = app.descendants(matching: .any)["tuner.floating.metronome"]
        XCTAssertTrue(floatingMetronome.waitForExistence(timeout: 5))
        floatingMetronome.tap()
        floatingMetronome.tap()

        let floatingStop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(floatingStop.waitForExistence(timeout: 5))
        floatingStop.tap()

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.recommendation"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["progress.allSessions"].exists)

        openTab("Settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))

        let advancedTuner = app.descendants(matching: .any)["settings.advancedTunerSettings"]
        XCTAssertTrue(waitForElementOrScroll(advancedTuner, in: app))
        XCTAssertFalse(app.descendants(matching: .any)["settings.referencePitchStepper"].exists)
        advancedTuner.tap()
        XCTAssertTrue(
            waitForElementOrScroll(app.descendants(matching: .any)["settings.referencePitchStepper"], in: app),
            "A4 should live behind Advanced tuner settings"
        )

        let soundToggle = app.switches["settings.metronomeSound"]
        XCTAssertTrue(waitForElementOrScroll(soundToggle, in: app))
        XCTAssertNotEqual(soundToggle.value as? String, "0", "Metronome sound should be enabled by default")
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.metronomeLink"], in: app))
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.scoresLink"], in: app))
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.privacyLink"], in: app))
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.termsLink"], in: app))
        XCTAssertTrue(waitForElementOrScroll(app.descendants(matching: .any)["settings.supportLink"], in: app))

        let clearData = app.descendants(matching: .any)["settings.clearLocalData"]
        XCTAssertTrue(waitForElementOrScroll(clearData, in: app))
        clearData.tap()
        assertDestructiveAlert(
            title: "Delete practice data?",
            destructiveButton: "Delete practice data",
            in: app,
            confirm: false
        )

        openTab("Progress", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5),
            "Cancel should preserve the saved recording"
        )

        openTab("Settings", in: app)
        let clearDataAgain = app.descendants(matching: .any)["settings.clearLocalData"]
        XCTAssertTrue(waitForElementOrScroll(clearDataAgain, in: app))
        clearDataAgain.tap()
        assertDestructiveAlert(
            title: "Delete practice data?",
            destructiveButton: "Delete practice data",
            in: app,
            confirm: true
        )

        openTab("Progress", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["progress.empty"].waitForExistence(timeout: 5),
            "Confirming the alert should clear local practice history"
        )

        openTab("Settings", in: app)
        let clearAllData = app.descendants(matching: .any)["settings.deleteAccount"]
        XCTAssertTrue(waitForElementOrScroll(clearAllData, in: app))
        clearAllData.tap()
        assertDestructiveAlert(
            title: "Clear all app data?",
            destructiveButton: "Clear all data",
            in: app,
            confirm: false
        )
    }

    @MainActor
    private func assertFourTabInformationArchitecture(in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar.buttons["Play-Along"].exists)
        XCTAssertTrue(tabBar.buttons["Tuner"].exists)
        XCTAssertTrue(tabBar.buttons["Progress"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
        XCTAssertEqual(tabBar.buttons.count, 4)

        for removedTab in ["Home", "Practice", "Analytics", "Coach", "More"] {
            XCTAssertFalse(tabBar.buttons[removedTab].exists, "\(removedTab) should not remain in the focused tab bar")
        }
    }

    @MainActor
    private func assertDestructiveAlert(
        title: String,
        destructiveButton: String,
        in app: XCUIApplication,
        confirm: Bool
    ) {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Destructive actions should use a native alert")
        XCTAssertEqual(alert.textFields.count, 0, "Destructive alerts must not require typed phrases")
        XCTAssertTrue(alert.buttons[destructiveButton].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        if confirm {
            alert.buttons[destructiveButton].tap()
        } else {
            alert.buttons["Cancel"].tap()
        }
    }

    @MainActor
    private func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: \.exists) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return elements.contains(where: \.exists)
    }

    @MainActor
    private func waitForElementOrScroll(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable {
                return true
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.10))
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func openTab(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabButton = app.tabBars.buttons[title]
        XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "\(title) tab should exist", file: file, line: line)
        tabButton.tap()
    }
}
