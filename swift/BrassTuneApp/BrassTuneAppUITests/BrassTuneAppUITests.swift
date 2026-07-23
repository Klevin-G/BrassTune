import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunGatewayAndInstrumentSetupLeadToTunerAndPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["gateway.continueAsGuest"].exists)
        XCTAssertTrue(app.buttons["gateway.signIn"].exists)
        XCTAssertTrue(app.buttons["gateway.createAccount"].exists)
        app.buttons["gateway.continueAsGuest"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.hero"].waitForExistence(timeout: 8),
            "The one-screen instrument setup should follow guest entry"
        )
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.hero"].label.contains("Choose your instrument"))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.hero"].label.contains("Step 1 of 1"))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.instrumentPicker"].exists)
        XCTAssertTrue(app.buttons["onboarding.startPractice"].exists)
        XCTAssertTrue(app.buttons["onboarding.notNow"].exists)
        tapWhenHittable(app.buttons["onboarding.startPractice"], in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 5),
            "Finishing setup should lead directly to Tuner"
        )

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.hero"].exists, "Completion must persist across relaunch")
    }

    @MainActor
    func testLaunchPracticeAndSettingsSurfaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        assertFiveTabInformationArchitecture(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8),
            "Tuner should be the first tab"
        )
        openTab("Play-Along", in: app)
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
        if targetNote.exists {
            XCTAssertTrue(app.descendants(matching: .any)["playAlong.holdProgress"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["playAlong.feedback"].exists)
        }
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
        XCTAssertTrue(tunerStart.waitForExistence(timeout: 10))
        tunerStart.tap()

        let floatingStopControl = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(floatingStopControl.waitForExistence(timeout: 8), "Recording should expose the floating practice transport")
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
        XCTAssertTrue(app.descendants(matching: .any)["settings.accountConfigurationUnavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "aren't configured in this build")).firstMatch.exists)

        let advancedTuner = app.descendants(matching: .any)["settings.advancedTunerSettings"]
        XCTAssertTrue(advancedTuner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["settings.referencePitchStepper"].exists)
        advancedTuner.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.referencePitchStepper"].waitForExistence(timeout: 8),
            "A4 should live behind Advanced tuner settings"
        )

        let soundToggle = app.switches["settings.metronomeSound"]
        XCTAssertTrue(soundToggle.waitForExistence(timeout: 5))
        XCTAssertNotEqual(soundToggle.value as? String, "0", "Metronome sound should be enabled by default")
        XCTAssertTrue(app.descendants(matching: .any)["settings.metronomeLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.scoresLink"].waitForExistence(timeout: 5))
        openTab("Class", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.classes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["classes.activePicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo brass studio"].exists)
        XCTAssertTrue(app.staticTexts["Second demo class"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["classes.leave.1"].exists)
        openTab("Settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.privacyLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.termsLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.supportLink"].waitForExistence(timeout: 5))

        let clearData = app.descendants(matching: .any)["settings.clearLocalData"]
        XCTAssertTrue(clearData.waitForExistence(timeout: 5))
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
        XCTAssertTrue(clearDataAgain.waitForExistence(timeout: 5))
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
        XCTAssertTrue(clearAllData.waitForExistence(timeout: 5))
        clearAllData.tap()
        assertDestructiveAlert(
            title: "Clear all app data?",
            destructiveButton: "Clear all data",
            in: app,
            confirm: false
        )
    }

    @MainActor
    func testLocalPracticeToolboxIsReachableFromFiveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        openTab("Play-Along", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["practice.quickStart.warmup"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Guided five-minute warm-up"].exists)
        XCTAssertTrue(app.buttons["Create a Play-Along exercise"].exists)
        XCTAssertTrue(app.buttons["Offline practice packs"].exists)
        XCTAssertTrue(app.buttons["Add to favorites"].exists)

        let builder = app.buttons["Create a Play-Along exercise"]
        tapWhenSafelyVisible(builder, in: app)
        XCTAssertTrue(app.navigationBars["Exercise builder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["exerciseBuilder.save"].exists)
        app.navigationBars.buttons["Play-Along"].tap()

        let warmup = app.buttons["Guided five-minute warm-up"]
        tapWhenSafelyVisible(warmup, in: app)
        XCTAssertTrue(app.navigationBars["Warm-up"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["warmup.start"].exists)
        app.navigationBars.buttons["Play-Along"].tap()

        let packs = app.buttons["Offline practice packs"]
        tapWhenSafelyVisible(packs, in: app)
        XCTAssertTrue(app.navigationBars["Practice packs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["practicePack.open.pack-daily-foundations"].exists)

        openTab("Tuner", in: app)
        let droneLink = app.descendants(matching: .any)["tuner.droneIntervalLink"]
        XCTAssertTrue(droneLink.waitForExistence(timeout: 5))
        droneLink.tap()
        XCTAssertTrue(app.navigationBars["Drone and intervals"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["drone.toggle"].exists)

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["progress.weeklyGoal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.weakTransition"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "at least three attempts"))
                .firstMatch
                .waitForExistence(timeout: 5),
            "The weak-transition card should explain the minimum evidence needed before generating a drill."
        )

        openTab("Settings", in: app)
        let metronomeLink = app.descendants(matching: .any)["settings.metronomeLink"]
        tapWhenSafelyVisible(metronomeLink, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["metronome.savePreset"].exists)
    }

    @MainActor
    private func assertFiveTabInformationArchitecture(in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertTrue(tabBar.buttons["Play-Along"].exists)
        XCTAssertTrue(tabBar.buttons["Tuner"].exists)
        XCTAssertTrue(tabBar.buttons["Progress"].exists)
        XCTAssertTrue(tabBar.buttons["Class"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
        XCTAssertEqual(tabBar.buttons.count, 5)

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
    private func tapWhenHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected tutorial control", file: file, line: line)
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Tutorial control should be reachable by scrolling", file: file, line: line)
        element.tap()
    }

    @MainActor
    private func tapWhenSafelyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected reachable control", file: file, line: line)
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 8 : 8
            let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 8 : app.frame.maxY - 8
            let frame = element.frame
            if frame.minY >= top, frame.maxY <= bottom, element.isHittable {
                element.tap()
                return
            }
            if frame.minY < top {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                    )
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
                    )
            }
        }
        XCTFail("Control never entered the unobscured area between the navigation and tab bars", file: file, line: line)
    }

    @MainActor
    private func assertTutorialCopy(
        _ fragment: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
            .firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "Missing tutorial explanation: \(fragment)", file: file, line: line)
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
