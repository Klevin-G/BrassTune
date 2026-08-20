import CryptoKit
import Foundation
import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunGuestInstrumentSetupLeadsToPracticeAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.continueAsGuest"].isHittable)
        app.descendants(matching: .any)["gateway.continueAsGuest"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.instrumentPicker"].isHittable)
        app.descendants(matching: .any)["onboarding.startPractice"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        assertPrimaryTabs(in: app)

        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["screen.instrumentSetup"].exists)
    }

    @MainActor
    func testExactPrimaryNavigationOrderAndReleaseHiddenFeatures() throws {
        let app = launchFixtureApp()
        assertPrimaryTabs(in: app)

        let expectedTabLabels = ["Practice", "Tuner", "Scales", "Progress", "More"]
        let tabBar = app.tabBars.firstMatch
        let tabLabels: [String]
        if tabBar.waitForExistence(timeout: 8) {
            tabLabels = (0..<tabBar.buttons.count).map { tabBar.buttons.element(boundBy: $0).label }
        } else {
            // On iPad, iOS 26 can expose the floating strip as ordinary buttons
            // rather than an XCUIElementTypeTabBar. Require one control for every
            // primary label, then preserve the exact visual left-to-right order.
            let floatingTabs = expectedTabLabels.map { title -> XCUIElement in
                let matches = app.descendants(matching: .button)
                    .matching(NSPredicate(format: "label == %@", title))
                let visibleMatches = matches.allElementsBoundByIndex.filter(\.isHittable)
                XCTAssertFalse(visibleMatches.isEmpty, "Missing floating primary tab: \(title)")
                guard let floatingTab = visibleMatches.first else { return matches.firstMatch }

                // XCTest can duplicate the same floating-strip node in the
                // accessibility tree. It is still one visual control only if
                // every hittable matching node shares that exact frame.
                XCTAssertTrue(
                    visibleMatches.allSatisfy { $0.frame == floatingTab.frame },
                    "Expected one visual floating primary tab: \(title)"
                )
                return floatingTab
            }
            XCTAssertTrue(floatingTabs.allSatisfy(\.isHittable))
            tabLabels = floatingTabs
                .sorted { $0.frame.minX < $1.frame.minX }
                .map(\.label)
        }
        XCTAssertEqual(tabLabels, expectedTabLabels)
        XCTAssertFalse(primaryTab("Class", in: app).exists)
        XCTAssertFalse(primaryTab("Settings", in: app).exists)

        openTab("More", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.more"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["more.classes"].exists)
        XCTAssertFalse(app.buttons["Offline practice packs"].exists)

        // Selection changes must replace the destination surface instead of overlaying it.
        openTab("Tuner", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen.practice"].exists)
        openTab("Scales", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen.tuner"].exists)

        openTab("Practice", in: app)
        let playAlongLibrary = app.descendants(matching: .any)["practice.playAlong"]
        XCTAssertTrue(playAlongLibrary.waitForExistence(timeout: 5))
        playAlongLibrary.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.playAlong"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.exercisePicker"].exists)
        XCTAssertTrue(app.staticTexts["Choose a clear next step"].exists)
        XCTAssertTrue(app.staticTexts["Any level · no microphone required"].exists)
        XCTAssertTrue(app.staticTexts["Complete five guided steps"].exists)
        XCTAssertFalse(app.buttons["Downloaded practice routines"].exists)
    }

    /// Exercises the orientations declared by the shipping target without
    /// depending on a physical iPad. This is simulator layout evidence only;
    /// it cannot replace physical rotation or uncoached usability checks.
    @MainActor
    func testSupportedOrientationsKeepPrimaryNavigationAndKeyControlsReachable() throws {
        let app = launchFixtureApp()
        defer { XCUIDevice.shared.orientation = .portrait }

        let orientations: [(name: String, value: UIDeviceOrientation, isLandscape: Bool)] = [
            ("Portrait", .portrait, false),
            ("Landscape left", .landscapeLeft, true),
            ("Landscape right", .landscapeRight, true),
        ]

        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation.value
            let expectedGeometry = NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                guard frame.width > 0, frame.height > 0 else { return false }
                return orientation.isLandscape
                    ? frame.width > frame.height
                    : frame.height > frame.width
            }
            let geometryExpectation = XCTNSPredicateExpectation(
                predicate: expectedGeometry,
                object: nil
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [geometryExpectation], timeout: 5),
                .completed,
                "\(orientation.name) must settle into the expected window geometry."
            )

            assertPrimaryTabs(in: app)

            openTab("Scales", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))
            let scaleStart = app.descendants(matching: .any)["scales.start"]
            bringIntoViewFromTop(scaleStart, in: app)
            XCTAssertTrue(scaleStart.isHittable, "Scale Start must remain reachable in \(orientation.name).")

            openTab("More", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.more"].waitForExistence(timeout: 5))
            let settings = app.descendants(matching: .any)["more.settings"]
            bringIntoViewFromTop(settings, in: app)
            XCTAssertTrue(settings.isHittable, "Settings must remain reachable in \(orientation.name).")

            openTab("Practice", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testDeniedMicrophoneShowsRecoveryWithoutReadyMeterOrFakeReading() throws {
        let app = launchFixtureApp(extraArguments: ["UITEST_MIC_DENIED"])
        openTab("Tuner", in: app)

        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 8))
        XCTAssertTrue(readout.label.contains("Microphone access is off"))
        XCTAssertTrue(readout.label.contains("Allow microphone access"))
        XCTAssertFalse(readout.label.contains("Ready"))
        XCTAssertFalse(app.descendants(matching: .any)["tuner.meter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.frequency"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.confidence"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.recordButton"].exists)

        let recovery = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Settings")).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 5), "Denied microphone state needs a recovery action")
    }

    @MainActor
    func testEstimatingFrameNeverExposesProvisionalTunerMeasurements() throws {
        let app = launchFixtureApp(extraArguments: ["UITEST_TUNER_ESTIMATING_FRAME"])
        openTab("Tuner", in: app)

        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 8))
        XCTAssertTrue(readout.label.contains("Finding your note"))
        XCTAssertTrue(readout.label.contains("Keep the note steady"))
        XCTAssertFalse(readout.label.contains("A4"))
        XCTAssertFalse(app.descendants(matching: .any)["tuner.meter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.frequency"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.confidence"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.instrument"].exists)
    }

    @MainActor
    func testStableTunerFrameShowsReadingMeasurementsAndMeter() throws {
        let app = launchFixtureApp(extraArguments: ["UITEST_TUNER_STABLE_FRAME"])
        openTab("Tuner", in: app)

        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 8))
        XCTAssertTrue(readout.label.contains("A4"))
        XCTAssertTrue(app.descendants(matching: .any)["tuner.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuner.frequency"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuner.confidence"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuner.instrument"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["tuner.meter"].exists)
    }

    @MainActor
    func testInteractiveWarmupCanExitPausedAndResumeFromPractice() throws {
        let app = launchFixtureApp()
        let warmup = app.descendants(matching: .any)["practice.warmup"]
        XCTAssertTrue(warmup.waitForExistence(timeout: 8))
        warmup.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.warmup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["warmup.start"].isHittable)
        app.descendants(matching: .any)["warmup.start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["warmup.breathingOrb"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "The primary tabs must not remain interactive behind an active warm-up")
        let pause = app.descendants(matching: .any)["warmup.pause"]
        bringIntoView(pause, in: app)
        pause.tap()

        app.buttons["warmup.exit"].tap()
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        app.buttons["Keep warm-up paused"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "Leaving a paused warm-up should restore normal navigation")
        XCTAssertTrue(app.descendants(matching: .any)["practice.resumeWarmup"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["practice.resumeWarmup"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.warmup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["warmup.start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScalesOffersAllRequiredOptionsAndVisualTimingWithoutMicrophone() throws {
        let app = launchFixtureApp()
        openTab("Scales", in: app)

        XCTAssertTrue(app.descendants(matching: .any)["scales.typePicker"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["scales.keyPicker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scales.octavesPicker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scales.directionPicker"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scales.notePreview"].exists)

        // Default trumpet practice cannot fit three complete octaves. Keep
        // that limitation explicit instead of silently substituting a shorter
        // exercise.
        let threeOctaveUnavailable = app.descendants(matching: .any)["scales.threeOctavesUnavailable"]
        XCTAssertTrue(threeOctaveUnavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(threeOctaveUnavailable.label.contains("unavailable"))

        let octavesPicker = app.descendants(matching: .any)["scales.octavesPicker"]
        octavesPicker.tap()
        let threeOctaves = app.buttons["Three octaves"]
        XCTAssertTrue(threeOctaves.waitForExistence(timeout: 5))
        XCTAssertTrue(threeOctaveUnavailable.exists, "An unavailable range must remain explicitly explained while the picker is open.")
        app.buttons["One octave"].tap()

        let typePicker = app.descendants(matching: .any)["scales.typePicker"]
        typePicker.tap()
        XCTAssertTrue(app.buttons["Harmonic minor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Melodic minor"].exists)
        XCTAssertTrue(app.buttons["Chromatic"].exists)
        app.buttons["Chromatic"].tap()

        let mode = app.descendants(matching: .any)["scales.practiceMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        bringIntoView(mode, in: app)
        let visualTiming = app.buttons["Visual timing"].firstMatch
        XCTAssertTrue(visualTiming.waitForExistence(timeout: 5))
        XCTAssertTrue(visualTiming.isHittable)
        visualTiming.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scales.visualTimingGuidance"].waitForExistence(timeout: 5))
        let start = app.descendants(matching: .any)["scales.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable, "The scale Start action should remain prominent without scrolling.")
        start.tap()

        // The destination's outer screen identifier is intentionally replaced by the
        // tab container in SwiftUI's accessibility tree. Assert the visible
        // visual-only control instead of relying on that container detail.
        XCTAssertTrue(app.descendants(matching: .any)["scales.visualTiming.currentNote"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["tuner.floating.stop"].exists)
        app.descendants(matching: .any)["scales.visualTiming.primary"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scales.visualTiming.primary"].waitForExistence(timeout: 5))
        let finish = app.descendants(matching: .any)["scales.visualTiming.finish"]
        XCTAssertTrue(finish.isHittable, "Visual timing must allow a user to exit without microphone access.")
        finish.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))

        // Tuba's documented practical written range supports D across three
        // octaves. Select a real fitting combination and prove that the app
        // enables and starts the requested range without widening any profile.
        openTab("More", in: app)
        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let instrumentPicker = app.descendants(matching: .any)["settings.instrumentPicker"]
        bringIntoView(instrumentPicker, in: app)
        instrumentPicker.tap()
        let tuba = app.buttons["Tuba"]
        XCTAssertTrue(tuba.waitForExistence(timeout: 5))
        tuba.tap()

        openTab("Scales", in: app)
        let keyPicker = app.descendants(matching: .any)["scales.keyPicker"]
        XCTAssertTrue(keyPicker.waitForExistence(timeout: 5))
        keyPicker.tap()
        let d = app.buttons["D"]
        XCTAssertTrue(d.waitForExistence(timeout: 5))
        d.tap()

        let tubaOctavesPicker = app.descendants(matching: .any)["scales.octavesPicker"]
        tubaOctavesPicker.tap()
        let enabledThreeOctaves = app.buttons["Three octaves"]
        XCTAssertTrue(enabledThreeOctaves.waitForExistence(timeout: 5))
        XCTAssertTrue(enabledThreeOctaves.isEnabled, "Tuba D must offer its real three-octave exercise.")
        enabledThreeOctaves.tap()
        XCTAssertFalse(app.descendants(matching: .any)["scales.threeOctavesUnavailable"].exists)

        let tubaMode = app.descendants(matching: .any)["scales.practiceMode"]
        bringIntoView(tubaMode, in: app)
        let tubaVisualTiming = app.buttons["Visual timing"].firstMatch
        XCTAssertTrue(tubaVisualTiming.waitForExistence(timeout: 5))
        tubaVisualTiming.tap()
        let tubaStart = app.descendants(matching: .any)["scales.start"]
        XCTAssertTrue(tubaStart.waitForExistence(timeout: 5))
        XCTAssertTrue(tubaStart.isEnabled)
        tubaStart.tap()
        let tubaCurrentNote = app.descendants(matching: .any)["scales.visualTiming.currentNote"]
        XCTAssertTrue(tubaCurrentNote.waitForExistence(timeout: 5))
        let tubaFinish = app.descendants(matching: .any)["scales.visualTiming.finish"]
        XCTAssertTrue(tubaFinish.waitForExistence(timeout: 5))
        tubaFinish.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoreRoutesToSettingsLegalAndClearData() throws {
        let app = launchFixtureApp()
        openTab("More", in: app)
        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let privacy = app.descendants(matching: .any)["more.privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        let settingsAgain = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settingsAgain.waitForExistence(timeout: 5))
        settingsAgain.tap()
        let clearData = app.descendants(matching: .any)["settings.clearLocalData"]
        bringIntoView(clearData, in: app)
        clearData.tap()
        let alert = app.alerts["Delete practice data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Delete practice history"].exists)
        alert.buttons["Cancel"].tap()
    }

    @MainActor
    func testPracticeQuickToolsExposeMetronomeAndAdvancedRhythm() throws {
        let app = launchFixtureApp()
        let metronome = app.descendants(matching: .any)["practice.metronome"]
        XCTAssertTrue(metronome.waitForExistence(timeout: 8))
        metronome.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["metronome.toggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["metronome.stepper"].exists)
        // The identifier is applied to the DisclosureGroup label's child text,
        // while the tappable accessibility element is its labelled button.
        let advanced = app.buttons["Advanced rhythm"]
        bringIntoView(advanced, in: app)
        advanced.tap()
        XCTAssertTrue(app.descendants(matching: .any)["metronome.beatUnitPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["metronome.accentFirstBeat"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["metronome.countIn"].exists)

        let toggle = app.descendants(matching: .any)["metronome.toggle"]
        for _ in 0..<20 {
            toggle.tap()
            toggle.tap()
        }
        XCTAssertTrue(toggle.isHittable)
    }

    @MainActor
    func testReleasePracticeCardsAndMoreDoNotDuplicateRoutes() throws {
        let app = launchFixtureApp()
        XCTAssertTrue(app.descendants(matching: .any)["practice.metronome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["practice.drone"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["practice.sheetMusic"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["practice.scales"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["practice.tuning"].exists)
        XCTAssertFalse(app.buttons["Offline practice packs"].exists)

        openTab("More", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.more"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["more.settings"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["more.metronome"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["more.drone"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["more.sheetMusic"].exists)

        for _ in 0..<5 {
            for title in ["Practice", "Tuner", "Scales", "Progress", "More"] {
                openTab(title, in: app)
            }
        }
        openTab("Practice", in: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLegalPagesShowCanonicalDocumentsAndSupportContact() throws {
        let app = launchFixtureApp()
        openTab("More", in: app)
        app.descendants(matching: .any)["more.settings"].tap()
        let privacy = app.descendants(matching: .any)["settings.privacyLink"]
        bringIntoView(privacy, in: app)
        privacy.tap()
        XCTAssertTrue(app.staticTexts["Published at the link below"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["https://brasstune.vercel.app/privacy"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        let terms = app.descendants(matching: .any)["settings.termsLink"]
        bringIntoView(terms, in: app)
        terms.tap()
        XCTAssertTrue(app.staticTexts["https://brasstune.vercel.app/terms"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Using BrassTune"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        let support = app.descendants(matching: .any)["settings.supportLink"]
        bringIntoView(support, in: app)
        support.tap()
        let email = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "brasstune1@gmail.com")
        ).firstMatch
        bringIntoView(email, in: app)
        XCTAssertTrue(email.exists)
        XCTAssertTrue(app.staticTexts["https://brasstune.vercel.app/support"].exists)
    }

    @MainActor
    func testPracticeDroneAndIntervalToolHasExplicitStopControl() throws {
        let app = launchFixtureApp()
        let drone = app.descendants(matching: .any)["practice.drone"]
        XCTAssertTrue(drone.waitForExistence(timeout: 8))
        drone.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["drone.targetNote"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["drone.interval"].exists)
        let toggle = app.descendants(matching: .any)["drone.toggle"]
        bringIntoView(toggle, in: app)
        XCTAssertTrue(toggle.label.contains("Play reference tone"))
        toggle.tap()
        XCTAssertTrue(app.buttons["Stop reference tone"].waitForExistence(timeout: 5))
        app.buttons["Stop reference tone"].tap()
        XCTAssertTrue(app.buttons["Play reference tone"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSheetMusicSampleSupportsViewerMetadataAndDeleteCancel() throws {
        let app = launchFixtureApp()
        let sheetMusic = app.descendants(matching: .any)["practice.sheetMusic"]
        XCTAssertTrue(sheetMusic.waitForExistence(timeout: 8))
        sheetMusic.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["score.import.files"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["score.import.photos"].exists)
        let sample = app.descendants(matching: .any)["score.import.testFixture"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 5))

        let attachLatest = app.descendants(matching: .any)["score.attachLatest"]
        bringIntoView(attachLatest, in: app)
        XCTAssertFalse(attachLatest.isEnabled, "A score cannot attach to a nonexistent session.")
        XCTAssertEqual(attachLatest.value as? String, "Unavailable", "Disabled secondary actions must announce that they are unavailable.")

        let fullPage = app.descendants(matching: .any)["score.viewFullPage"]
        bringIntoView(fullPage, in: app)
        XCTAssertTrue(fullPage.isHittable)
        fullPage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.fullPageViewer"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["score.viewer.done"].tap()

        let actions = app.descendants(matching: .any)["score.actions"]
        bringIntoView(actions, in: app)
        actions.tap()
        let rename = app.descendants(matching: .any)["score.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let renameField = app.textFields["Score title"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.tap()
        renameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 120))
        renameField.typeText("Renamed fixture score")
        app.alerts["Rename score"].buttons["Rename"].tap()
        XCTAssertTrue(app.staticTexts["Renamed fixture score"].waitForExistence(timeout: 5))

        actions.tap()
        let metadata = app.descendants(matching: .any)["score.export"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertTrue(metadata.isHittable)
        let delete = app.descendants(matching: .any)["score.delete"]
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertTrue(app.buttons["Delete local score"].waitForExistence(timeout: 5))
        app.buttons["Keep score"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.card"].exists)
    }

    @MainActor
    func testPracticeTabReturnsToPracticeHomeAfterOpeningDrone() throws {
        let app = launchFixtureApp()
        app.descendants(matching: .any)["practice.drone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 5))

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.progress"].waitForExistence(timeout: 5))
        openTab("Practice", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["practice.drone"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["screen.droneInterval"].exists)
    }

    @MainActor
    func testScoreGuidedPracticeIsManualAndHasAllNotesRoutine() throws {
        let app = launchFixtureApp()
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        app.descendants(matching: .any)["score.import.testFixture"].tap()
        let start = app.descendants(matching: .any)["score.startGuidedPractice"]
        bringIntoView(start, in: app)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.guided.allNotes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["score.guided.begin"].isHittable)
        app.descendants(matching: .any)["score.guided.begin"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.guided.pause"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["score.guided.cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScoreGuidedPracticeBackgroundPausesTimerAndSavesManualSession() throws {
        let app = launchFixtureApp()
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5))

        let fixture = app.descendants(matching: .any)["score.import.testFixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        fixture.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 5))

        let start = app.descendants(matching: .any)["score.startGuidedPractice"]
        bringIntoView(start, in: app)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.guided.allNotes"].waitForExistence(timeout: 5))

        let begin = app.descendants(matching: .any)["score.guided.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()

        let elapsed = app.descendants(matching: .any)["score.guided.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let elapsedDisplay = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", ".*[0-9]{2}:[0-9]{2}.*")
        ).firstMatch
        XCTAssertTrue(elapsedDisplay.waitForExistence(timeout: 5))
        sleep(2)

        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        let resume = app.descendants(matching: .any)["score.guided.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8), "Backgrounding an active routine must return it paused.")
        let pausedElapsedLabel = elapsedDisplay.label
        sleep(2)
        XCTAssertEqual(
            elapsedDisplay.label,
            pausedElapsedLabel,
            "Elapsed active time must remain stable while the background-paused routine is idle."
        )

        resume.tap()
        let finish = app.descendants(matching: .any)["score.guided.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        let done = app.descendants(matching: .any)["score.guided.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Finishing must save the manual score-practice session.")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5))

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.progress"].waitForExistence(timeout: 5))
        let allSessions = app.descendants(matching: .any)["progress.allSessions"]
        bringIntoView(allSessions, in: app)
        allSessions.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.sessions"].waitForExistence(timeout: 5))

        let savedSessionName = app.descendants(matching: .any)["sessions.sessionName"]
        XCTAssertTrue(savedSessionName.waitForExistence(timeout: 5))
        XCTAssertEqual(savedSessionName.label, "Long-tone study")
    }

    @MainActor
    func testProgressShowsSavedHistoryAndDeniedMicGetsNonTunerRecommendation() throws {
        let app = launchFixtureApp()
        openTab("Tuner", in: app)
        let start = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.allSessions"].exists)

        app.terminate()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE", "UITEST_MIC_DENIED"]
        app.launch()
        openTab("Progress", in: app)
        XCTAssertTrue(app.staticTexts["5-minute warm-up"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["3-minute tuning check"].exists)
        let nextStepCTA = app.descendants(matching: .any)["progress.nextStep.cta"]
        bringIntoView(nextStepCTA, in: app)
        XCTAssertTrue(nextStepCTA.waitForExistence(timeout: 5), "A no-mic recommendation must provide a non-tuner CTA")
        nextStepCTA.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.warmup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen.tuner"].exists)
    }

    @MainActor
    func testSettingsExportAndDestructiveScopesStayDistinct() throws {
        let app = launchFixtureApp()
        openTab("More", in: app)
        app.descendants(matching: .any)["more.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))

        let export = app.descendants(matching: .any)["settings.exportData"]
        bringIntoView(export, in: app)
        XCTAssertTrue(export.isHittable)
        let clearHistory = app.descendants(matching: .any)["settings.clearLocalData"]
        bringIntoView(clearHistory, in: app)
        clearHistory.tap()
        let historyAlert = app.alerts["Delete practice data?"]
        XCTAssertTrue(historyAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(historyAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Imported sheet music")).firstMatch.exists)
        XCTAssertTrue(historyAlert.buttons["Delete practice history"].exists)
        historyAlert.buttons["Cancel"].tap()

        let clearAll = app.descendants(matching: .any)["settings.deleteAccount"]
        bringIntoView(clearAll, in: app)
        clearAll.tap()
        let allAlert = app.alerts["Clear all app data?"]
        XCTAssertTrue(allAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(allAlert.buttons["Clear all data"].exists)
        allAlert.buttons["Cancel"].tap()
    }

    @MainActor
    func testMaximumDynamicTypeAndRTLKeepVisibleNavigationReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_FIXTURES", "UITEST_RESET_STATE", "UITEST_RTL",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        XCTAssertEqual(tabs.buttons.count, 5)
        let scales = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(scales.isHittable)
        XCTAssertGreaterThanOrEqual(scales.frame.height, 44)
        scales.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scales.notePreview"].exists)
        let scaleStart = app.descendants(matching: .any)["scales.start"]
        bringIntoView(scaleStart, in: app)
    }

    @MainActor
    func testAccountFormShowsInlineValidationAndLegalLinks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launchEnvironment = [
            "BRASSTUNE_ENV": "production",
            "BRASSTUNE_API_BASE_URL": "https://brasstune-u8qj.onrender.com",
            "BRASSTUNE_SUPABASE_URL": "https://project.supabase.co",
            "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
        ]
        app.launch()

        let createAccount = app.descendants(matching: .any)["gateway.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 8))
        createAccount.tap()
        let email = app.descendants(matching: .any)["gateway.email"]
        let password = app.descendants(matching: .any)["gateway.password"]
        let privacy = app.descendants(matching: .any)["gateway.privacyLink"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.termsLink"].exists)
        bringIntoView(email, in: app)
        email.tap()
        email.typeText("invalid-email")
        password.tap()
        password.typeText("short")

        XCTAssertTrue(app.descendants(matching: .any)["gateway.emailError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.passwordError"].exists)
        XCTAssertFalse(app.buttons["gateway.submitAuth"].firstMatch.isEnabled)
    }

    @MainActor
    func testGoogleProviderRendersWithoutAppleWhenOnlyGoogleIsConfigured() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_STATE",
            "UITEST_ENTRY_FLOW",
            "UITEST_AUTH_PROVIDERS",
        ]
        app.launchEnvironment = [
            "BRASSTUNE_ENV": "production",
            "BRASSTUNE_API_BASE_URL": "https://brasstune-u8qj.onrender.com",
            "BRASSTUNE_SUPABASE_URL": "https://project.supabase.co",
            "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
        ]
        app.launch()

        let createAccount = app.descendants(matching: .any)["gateway.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 8))
        createAccount.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gateway.authGoogleSignIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["gateway.authAppleSignIn"].exists)
    }

    /// System maximum Dynamic Type and RTL are intentionally launched together:
    /// this catches controls that remain reachable only in the default LTR size.
    @MainActor
    func testMaximumDynamicTypeRTLPrimaryTargetsRemainAtLeast44Points() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_FIXTURES",
            "UITEST_RESET_STATE",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleLanguages",
            "(ar)",
            "-AppleLocale",
            "ar",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))
        XCTAssertEqual(tabBar.buttons.count, 5)
        XCTAssertTrue(tabBar.buttons["يمارس"].exists, "Arabic launch must localize the Practice tab, not only mirror its layout.")
        XCTAssertTrue(tabBar.buttons["المقاييس"].exists, "Arabic launch must localize the Scales tab.")
        XCTAssertTrue(tabBar.buttons["أكثر"].exists, "Arabic launch must localize the More tab.")
        for index in 0..<tabBar.buttons.count {
            let tab = tabBar.buttons.element(boundBy: index)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, "Primary tab \(index) must retain a 44-point target at maximum Dynamic Type in RTL.")
            XCTAssertTrue(tab.isHittable)
        }

        tabBar.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 5))
        let scaleStart = app.descendants(matching: .any)["scales.start"]
        bringIntoView(scaleStart, in: app)
        XCTAssertGreaterThanOrEqual(scaleStart.frame.height, 44)

        tabBar.buttons.element(boundBy: 4).tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.more"].waitForExistence(timeout: 5))
        let settings = app.descendants(matching: .any)["more.settings"]
        bringIntoView(settings, in: app)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertTrue(settings.isHittable)

        tabBar.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 5))
        let scorePractice = app.descendants(matching: .any)["practice.sheetMusic"]
        bringIntoView(scorePractice, in: app)
        XCTAssertGreaterThanOrEqual(scorePractice.frame.height, 44)
        scorePractice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 5))
        let fixture = app.descendants(matching: .any)["score.import.testFixture"]
        bringIntoView(fixture, in: app)
        fixture.tap()

        let guided = app.descendants(matching: .any)["score.startGuidedPractice"]
        bringIntoView(guided, in: app)
        XCTAssertGreaterThanOrEqual(guided.frame.height, 44)
        XCTAssertTrue(guided.isHittable)

        let actions = app.descendants(matching: .any)["score.actions"]
        let scorePracticeScroll = app.scrollViews["screen.scorePractice"].firstMatch
        XCTAssertTrue(scorePracticeScroll.waitForExistence(timeout: 5))
        // At maximum Dynamic Type, the multiline practice-notes field occupies
        // the usual swipe path. Drag the enclosing score-practice scroll view
        // through its right gutter so XCTest cannot focus or capture the field.
        for _ in 0..<6 where !actions.isHittable {
            let gutterStart = scorePracticeScroll.coordinate(
                withNormalizedOffset: CGVector(dx: 0.96, dy: 0.72)
            )
            let gutterEnd = scorePracticeScroll.coordinate(
                withNormalizedOffset: CGVector(dx: 0.96, dy: 0.28)
            )
            gutterStart.press(forDuration: 0.05, thenDragTo: gutterEnd)
        }
        XCTAssertTrue(actions.isHittable, "Score actions must remain reachable without interacting with the practice-notes field.")
        XCTAssertGreaterThanOrEqual(actions.frame.height, 44)
        actions.tap()
        let rename = app.descendants(matching: .any)["score.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(rename.frame.height, 44)
    }

#if PHYSICAL_RELEASE
    /// Real-device-only probe that preserves the Control Center state used to
    /// validate the screen-recorder variants without toggling any controls.
    @MainActor
    func testPhysicalReleaseControlCenterProbe() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let topRight = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01))
        let controlCenter = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25))
        topRight.press(forDuration: 0.05, thenDragTo: controlCenter)
        sleep(2)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Physical Control Center recorder-state probe"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("PHYSICAL_CONTROL_CENTER_PROBE_BEGIN")
        print(springboard.debugDescription)
        print("PHYSICAL_CONTROL_CENTER_PROBE_END")

        XCTAssertTrue(
            springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Screen Recording"))
                .firstMatch
                .waitForExistence(timeout: 5),
            "Control Center must expose the Screen Recording control on the physical device."
        )
    }

    /// Expands the real Control Center output-route picker and preserves the
    /// available-route hierarchy without selecting or changing a destination.
    @MainActor
    func testPhysicalReleaseAirPlayRouteAvailabilityProbe() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openPhysicalControlCenter(in: springboard)
        let routeButton = springboard.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@", "mru-router-upper", "AirPlay")
        ).firstMatch
        XCTAssertTrue(routeButton.waitForExistence(timeout: 8), "Control Center must expose the system audio-route picker.")
        routeButton.tap()
        sleep(2)

        let routePicker = springboard.collectionViews["Route Picker Items"]
        XCTAssertTrue(routePicker.waitForExistence(timeout: 8), "The system audio-route list must open before availability is classified.")
        preservePhysicalScreenshot(named: "Physical Control Center AirPlay route availability")
        print("PHYSICAL_AUDIO_ROUTE_AVAILABILITY_BEGIN")
        print(routePicker.debugDescription)
        print("PHYSICAL_AUDIO_ROUTE_AVAILABILITY_END")
    }

    /// Verifies the compile-gated in-app route picker used to keep the audio
    /// graph alive while the system route sheet is presented.
    @MainActor
    func testPhysicalReleaseInAppRoutePickerAvailabilityProbe() throws {
        let app = launchPhysicalReleaseApp(extraArguments: ["UITEST_PHYSICAL_ROUTE_PICKER"])
        let routeControl = app.descendants(matching: .any)["physical.routePicker"]
        XCTAssertTrue(routeControl.waitForExistence(timeout: 8), "The physical-only in-app route picker must be present.")
        routeControl.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var routePicker = springboard.collectionViews["Route Picker Items"]
        if !routePicker.waitForExistence(timeout: 3) {
            routePicker = app.collectionViews["Route Picker Items"]
        }
        preservePhysicalScreenshot(named: "Physical in-app AirPlay route availability")
        print("PHYSICAL_IN_APP_ROUTE_PICKER_APP_BEGIN")
        print(app.debugDescription)
        print("PHYSICAL_IN_APP_ROUTE_PICKER_APP_END")
        print("PHYSICAL_IN_APP_ROUTE_PICKER_SYSTEM_BEGIN")
        print(springboard.debugDescription)
        print("PHYSICAL_IN_APP_ROUTE_PICKER_SYSTEM_END")
        XCTAssertTrue(routePicker.waitForExistence(timeout: 8), "The in-app picker must present the real system route list.")
    }

    /// Exercises an actually advertised AirPlay destination while BrassTune owns
    /// an output graph, then restores the built-in speaker and proves that a new
    /// graph can start. The destination is discovered from Control Center at run
    /// time so this test never claims unavailable Bluetooth or wired hardware.
    @MainActor
    func testPhysicalReleaseAirPlayRouteChangeAndRecovery() throws {
        let app = launchPhysicalReleaseApp(extraArguments: ["UITEST_PHYSICAL_ROUTE_PICKER"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openTab("Practice", in: app)

        // A failed or interrupted prior route run can leave the device routed
        // to AirPlay. Establish a deterministic built-in-speaker baseline
        // before the reference graph starts.
        var routePicker = openPhysicalInAppRoutePicker(in: app, springboard: springboard)
        let baselineSpeaker = routePicker.cells.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "iPhone Speaker", "LOCAL::Speaker")
        ).firstMatch
        XCTAssertTrue(baselineSpeaker.waitForExistence(timeout: 8), "The active-route test must establish the iPhone speaker baseline.")
        baselineSpeaker.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.descendants(matching: .any)["practice.drone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))

        let toneToggle = app.buttons["drone.toggle"]
        XCTAssertTrue(toneToggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toneToggle.label, "Play reference tone")
        toneToggle.tap()
        XCTAssertTrue(
            waitForPhysicalElement(toneToggle, toHaveLabel: "Stop reference tone", timeout: 12),
            "Reference tone must be active before the route changes."
        )
        preservePhysicalScreenshot(named: "Physical reference tone before AirPlay route change")

        routePicker = openPhysicalInAppRoutePicker(in: app, springboard: springboard)
        let externalRoute = routePicker.cells.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "HomePod")
        ).firstMatch
        XCTAssertTrue(externalRoute.waitForExistence(timeout: 8), "The available Office HomePod route must be present for the active-route test.")
        let externalRouteName = externalRoute.label
        NSLog("PHYSICAL_AIRPLAY_ROUTE_SELECTED: %@", externalRouteName)
        externalRoute.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        // AVRoutePickerView keeps its system sheet open after route selection
        // on iOS 26.4.1. Dismiss the sheet before probing the app; otherwise
        // SpringBoard, not BrassTune, consumes the next synthesized tap.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8), "BrassTune must remain alive after a real AirPlay route change.")
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForPhysicalElement(toneToggle, toHaveLabel: "Stop reference tone", timeout: 8),
            "Reference tone must remain active across the in-app AirPlay route switch."
        )
        let targetNote = app.descendants(matching: .any)["drone.targetNote"]
        let initialTargetLabel = targetNote.label
        let incrementNote = app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "Increment", "drone.noteStepper-Increment")
        ).firstMatch
        XCTAssertTrue(incrementNote.waitForExistence(timeout: 8), "The live Drone note stepper must remain available on AirPlay.")
        incrementNote.tap()
        XCTAssertTrue(
            waitForPhysicalElement(targetNote, toChangeFromLabel: initialTargetLabel, timeout: 8),
            "The Drone UI and live graph must accept a note change immediately after switching to AirPlay."
        )
        let externalTargetLabel = targetNote.label
        NSLog("PHYSICAL_AIRPLAY_EXTERNAL_INTERACTIVITY_PASSED: %@ -> %@", initialTargetLabel, externalTargetLabel)
        preservePhysicalScreenshot(named: "Physical active reference tone on external AirPlay route")

        routePicker = openPhysicalControlCenterRoutePicker(in: springboard)
        let builtInSpeaker = routePicker.cells.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "iPhone Speaker", "LOCAL::Speaker")
        ).firstMatch
        XCTAssertTrue(builtInSpeaker.waitForExistence(timeout: 8), "The test must be able to restore the phone's built-in speaker.")
        builtInSpeaker.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForPhysicalElement(toneToggle, toHaveLabel: "Stop reference tone", timeout: 8),
            "Reference tone must remain active when the live graph returns to the iPhone speaker."
        )
        let decrementNote = app.buttons.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "Decrement", "drone.noteStepper-Decrement")
        ).firstMatch
        XCTAssertTrue(decrementNote.waitForExistence(timeout: 8), "The live Drone note stepper must remain available after returning to the speaker.")
        decrementNote.tap()
        XCTAssertTrue(
            waitForPhysicalElement(targetNote, toChangeFromLabel: externalTargetLabel, timeout: 8),
            "The Drone UI and live graph must accept a note change after returning to the iPhone speaker."
        )
        NSLog("PHYSICAL_AIRPLAY_SPEAKER_INTERACTIVITY_PASSED: %@ -> %@", externalTargetLabel, targetNote.label)
        openTab("Tuner", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        openTab("Practice", in: app)
        app.descendants(matching: .any)["practice.drone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForPhysicalElement(app.buttons["drone.toggle"], toHaveLabel: "Play reference tone", timeout: 8),
            "Leaving the feature must release the live tone owner after the AirPlay round trip."
        )
        preservePhysicalScreenshot(named: "Physical active reference tone completed AirPlay round trip")
    }

    /// Repeats the real AirPlay round trip while the metronome is scheduling
    /// buffers, directly exercising the historical ScheduleBuffer crash family
    /// against a physical route transition before rebuilding on the phone.
    @MainActor
    func testPhysicalReleaseMetronomeAirPlayRouteChangeAndRecovery() throws {
        let app = launchPhysicalReleaseApp(extraArguments: ["UITEST_PHYSICAL_ROUTE_PICKER"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openTab("Practice", in: app)

        var routePicker = openPhysicalInAppRoutePicker(in: app, springboard: springboard)
        let baselineSpeaker = routePicker.cells.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "iPhone Speaker", "LOCAL::Speaker")
        ).firstMatch
        XCTAssertTrue(baselineSpeaker.waitForExistence(timeout: 8), "The Metronome route test must establish the iPhone speaker baseline.")
        baselineSpeaker.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        app.descendants(matching: .any)["practice.metronome"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))

        let metronomeToggle = app.descendants(matching: .any)["metronome.toggle"]
        XCTAssertTrue(metronomeToggle.waitForExistence(timeout: 8))
        metronomeToggle.tap()
        XCTAssertTrue(app.buttons["Stop metronome"].waitForExistence(timeout: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        preservePhysicalScreenshot(named: "Physical metronome before AirPlay route change")

        routePicker = openPhysicalInAppRoutePicker(in: app, springboard: springboard)
        let externalRoute = routePicker.cells.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "HomePod")
        ).firstMatch
        XCTAssertTrue(externalRoute.waitForExistence(timeout: 8), "The available Office HomePod route must be present for the live Metronome test.")
        NSLog("PHYSICAL_METRONOME_AIRPLAY_ROUTE_SELECTED: %@", externalRoute.label)
        externalRoute.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8), "BrassTune must remain alive while metronome buffers cross a real route transition.")
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Stop metronome"].waitForExistence(timeout: 8), "Metronome must remain active while buffers cross the AirPlay route switch.")
        let bpm = app.descendants(matching: .any)["metronome.bpm"]
        let externalBPM = bpm.label
        let tempoUp = app.descendants(matching: .any)["metronome.tempoUp"]
        XCTAssertTrue(tempoUp.waitForExistence(timeout: 8))
        tempoUp.tap()
        XCTAssertTrue(
            waitForPhysicalElement(bpm, toChangeFromLabel: externalBPM, timeout: 8),
            "The active Metronome must accept a tempo change on AirPlay."
        )
        let raisedBPM = bpm.label
        NSLog("PHYSICAL_METRONOME_EXTERNAL_INTERACTIVITY_PASSED: %@ -> %@", externalBPM, raisedBPM)
        preservePhysicalScreenshot(named: "Physical active Metronome on external AirPlay route")

        routePicker = openPhysicalControlCenterRoutePicker(in: springboard)
        let builtInSpeaker = routePicker.cells.matching(
            NSPredicate(format: "label == %@ OR identifier == %@", "iPhone Speaker", "LOCAL::Speaker")
        ).firstMatch
        XCTAssertTrue(builtInSpeaker.waitForExistence(timeout: 8), "The metronome route test must restore the phone speaker.")
        builtInSpeaker.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Stop metronome"].waitForExistence(timeout: 8), "Metronome must remain active when the live graph returns to the iPhone speaker.")
        let tempoDown = app.descendants(matching: .any)["metronome.tempoDown"]
        XCTAssertTrue(tempoDown.waitForExistence(timeout: 8))
        tempoDown.tap()
        XCTAssertTrue(
            waitForPhysicalElement(bpm, toChangeFromLabel: raisedBPM, timeout: 8),
            "The active Metronome must accept a tempo change after returning to the iPhone speaker."
        )
        NSLog("PHYSICAL_METRONOME_SPEAKER_INTERACTIVITY_PASSED: %@ -> %@", raisedBPM, bpm.label)
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2))
        openTab("Tuner", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        openTab("Practice", in: app)
        app.descendants(matching: .any)["practice.metronome"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Start metronome"].waitForExistence(timeout: 8))
        preservePhysicalScreenshot(named: "Physical active Metronome completed AirPlay round trip")
    }

    /// Adds the Screen Recording control on a newly provisioned test phone when
    /// the owner has not already placed it in Control Center. This setup remains
    /// isolated to the physical release test device and never starts a recording.
    @MainActor
    func testPhysicalReleaseEnsureScreenRecordingControl() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openPhysicalControlCenter(in: springboard)

        let existing = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Screen Recording"))
            .firstMatch
        if existing.waitForExistence(timeout: 2) {
            preservePhysicalScreenshot(named: "Screen Recording control already available")
            return
        }

        let addControls = springboard.buttons["Add Controls"]
        XCTAssertTrue(
            addControls.waitForExistence(timeout: 5),
            "Control Center must expose Add Controls before physical recording setup."
        )
        addControls.tap()
        sleep(2)

        // iOS 26 first enters Control Center edit mode. The gallery is opened
        // by the explicit bottom action rather than the top-left edit button.
        let openGallery = springboard.buttons["Add a Control"]
        if openGallery.waitForExistence(timeout: 3) {
            openGallery.tap()
            sleep(2)
        }

        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Screen Recording")
            sleep(1)
        }

        print("PHYSICAL_CONTROL_GALLERY_BEGIN")
        print(springboard.debugDescription)
        print("PHYSICAL_CONTROL_GALLERY_END")
        preservePhysicalScreenshot(named: "Control gallery Screen Recording search")

        let candidate = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Screen Recording"))
            .firstMatch
        XCTAssertTrue(
            candidate.waitForExistence(timeout: 8),
            "The iOS Control Gallery must offer Screen Recording on the physical test phone."
        )
        candidate.tap()
        sleep(2)

        XCUIDevice.shared.press(.home)
        openPhysicalControlCenter(in: springboard)
        let installed = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Screen Recording"))
            .firstMatch
        XCTAssertTrue(
            installed.waitForExistence(timeout: 8),
            "Screen Recording must remain available after it is added to Control Center."
        )
        preservePhysicalScreenshot(named: "Screen Recording control added")
    }

    /// Prepares the original TestFlight reproduction condition while proving
    /// the narration microphone is disabled before the recorder starts.
    @MainActor
    func testPhysicalReleasePrepareScreenRecordingMicrophoneOff() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openPhysicalControlCenter(in: springboard)

        let recording = springboard.buttons["Screen Recording"]
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.press(forDuration: 1.0)
        sleep(2)
        preservePhysicalScreenshot(named: "Screen Recording options before microphone-off start")
        print("PHYSICAL_SCREEN_RECORDING_OPTIONS_BEGIN")
        print(springboard.debugDescription)
        print("PHYSICAL_SCREEN_RECORDING_OPTIONS_END")

        var microphone = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Microphone"))
            .firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 5), "Screen Recording options must expose the narration microphone state.")

        var microphoneState = (microphone.value as? String)?.lowercased() ?? "unknown"
        if microphone.isSelected || microphoneState == "on" || microphoneState == "1" {
            microphone.tap()
            sleep(1)
            microphone = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Microphone"))
                .firstMatch
            microphoneState = (microphone.value as? String)?.lowercased() ?? "unknown"
        }
        print("PHYSICAL_SCREEN_RECORDING_MICROPHONE_OFF_STATE=\(microphoneState) selected=\(microphone.isSelected)")
        XCTAssertFalse(microphone.isSelected)
        XCTAssertEqual(microphoneState, "off")
        preservePhysicalScreenshot(named: "Screen Recording narration microphone off")

        let start = springboard.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Start Recording")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        sleep(5)

        app.activate()
        preservePhysicalScreenshot(named: "Screen Recording active with narration microphone off")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    /// Stops an already-active device recording through its explicit expanded
    /// Control Center action so an inactive control is never tapped by mistake.
    @MainActor
    func testPhysicalReleaseStopActiveScreenRecording() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openPhysicalControlCenter(in: springboard)
        let recording = springboard.buttons["Screen Recording"]
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.press(forDuration: 1.0)
        sleep(2)
        preservePhysicalScreenshot(named: "Screen Recording active before stop")

        let stop = springboard.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Stop Recording")
        ).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "The physical recorder must be active before it is stopped.")
        stop.tap()
        sleep(4)
        app.activate()
        preservePhysicalScreenshot(named: "Screen Recording stopped and saved")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    /// Prepares the original build-2 discovery condition with narration audio
    /// enabled and proves the Control Center microphone state before starting.
    @MainActor
    func testPhysicalReleasePrepareScreenRecordingMicrophoneOn() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openPhysicalControlCenter(in: springboard)
        let recording = springboard.buttons["Screen Recording"]
        XCTAssertTrue(recording.waitForExistence(timeout: 5))
        recording.press(forDuration: 1.0)
        sleep(2)

        var microphone = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Microphone"))
            .firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        var microphoneState = (microphone.value as? String)?.lowercased() ?? "unknown"
        if !microphone.isSelected && microphoneState != "on" && microphoneState != "1" {
            microphone.tap()
            sleep(1)
            microphone = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Microphone"))
                .firstMatch
            microphoneState = (microphone.value as? String)?.lowercased() ?? "unknown"
        }
        print("PHYSICAL_SCREEN_RECORDING_MICROPHONE_ON_STATE=\(microphoneState) selected=\(microphone.isSelected)")
        XCTAssertEqual(microphoneState, "on")
        preservePhysicalScreenshot(named: "Screen Recording narration microphone on")

        let start = springboard.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Start Recording")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        sleep(5)
        app.activate()
        preservePhysicalScreenshot(named: "Screen Recording active with narration microphone on")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    private func openPhysicalControlCenter(in springboard: XCUIApplication) {
        let topRight = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01))
        let controlCenter = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.25))
        topRight.press(forDuration: 0.05, thenDragTo: controlCenter)
        sleep(2)
    }

    @MainActor
    private func openPhysicalControlCenterRoutePicker(
        in springboard: XCUIApplication
    ) -> XCUIElement {
        openPhysicalControlCenter(in: springboard)
        let routeButton = springboard.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@", "mru-router-upper", "AirPlay")
        ).firstMatch
        XCTAssertTrue(
            routeButton.waitForExistence(timeout: 8),
            "Control Center must expose the system audio-route picker."
        )
        routeButton.tap()

        let routePicker = springboard.collectionViews["Route Picker Items"]
        XCTAssertTrue(
            routePicker.waitForExistence(timeout: 8),
            "Control Center must expose the route list while the test-only graph remains active."
        )
        return routePicker
    }

    @MainActor
    private func openPhysicalInAppRoutePicker(
        in app: XCUIApplication,
        springboard: XCUIApplication
    ) -> XCUIElement {
        let routeControl = app.descendants(matching: .any)["physical.routePicker"]
        XCTAssertTrue(
            routeControl.waitForExistence(timeout: 8),
            "The physical-only in-app audio-route control must be available."
        )
        let systemRouteButton = app.buttons["AirPlay"]
        if systemRouteButton.waitForExistence(timeout: 2) {
            systemRouteButton.tap()
        } else {
            routeControl.tap()
        }

        var routePicker = springboard.collectionViews["Route Picker Items"]
        if !routePicker.waitForExistence(timeout: 3) {
            routePicker = app.collectionViews["Route Picker Items"]
        }
        XCTAssertTrue(
            routePicker.waitForExistence(timeout: 8),
            "The system audio-route list must open without backgrounding BrassTune."
        )
        return routePicker
    }

    @MainActor
    private func waitForPhysicalElement(
        _ element: XCUIElement,
        toHaveLabel expectedLabel: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, element.label == expectedLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return element.exists && element.label == expectedLabel
    }

    @MainActor
    private func waitForPhysicalElement(
        _ element: XCUIElement,
        toChangeFromLabel initialLabel: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists, element.label != initialLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return element.exists && element.label != initialLabel
    }

    @MainActor
    private func preservePhysicalScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPhysicalReleaseSystemTimerInterruptionAndRecovery() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let springboardStop = springboard.buttons["Stop"]
        if springboardStop.waitForExistence(timeout: 2) {
            springboardStop.tap()
        }

        let clock = XCUIApplication(bundleIdentifier: "com.apple.mobiletimer")
        clock.launch()
        XCTAssertTrue(clock.wait(for: .runningForeground, timeout: 8))
        let timers = clock.tabBars.buttons["Timers"]
        XCTAssertTrue(timers.waitForExistence(timeout: 5))
        timers.tap()

        let wheels = clock.pickerWheels
        XCTAssertEqual(wheels.count, 3)
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "0 hours")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "0 min")
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: "30 sec")
        let startTimer = clock.buttons["Start"]
        XCTAssertTrue(startTimer.isHittable)
        startTimer.tap()

        let app = XCUIApplication()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        if app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 3) {
            app.descendants(matching: .any)["gateway.continueAsGuest"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 8))
            app.descendants(matching: .any)["onboarding.startPractice"].tap()
        }
        if app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 3) {
            openTab("Tuner", in: app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))

        let captureStart = app.descendants(matching: .any)["tuner.recordButton"]
        let captureStop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(captureStart.waitForExistence(timeout: 8))
        captureStart.tap()
        allowMicrophonePermissionIfPresented()
        XCTAssertTrue(captureStop.waitForExistence(timeout: 15))

        var timerStop: XCUIElement?
        for _ in 0..<45 {
            if springboardStop.exists {
                timerStop = springboardStop
                break
            }
            sleep(1)
        }
        XCTAssertNotNil(timerStop, "The on-device 30-second timer must present its real Stop action.")
        preservePhysicalScreenshot(named: "Physical on-device timer interrupted live Tuner")
        let interruptedHierarchy = XCTAttachment(string: app.debugDescription)
        interruptedHierarchy.name = "BrassTune hierarchy while physical timer alarm is active"
        interruptedHierarchy.lifetime = .keepAlways
        add(interruptedHierarchy)
        timerStop?.tap()

        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        XCTAssertFalse(captureStop.exists, "Timer interruption must tear down the active capture.")
        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertFalse(readout.label.contains("Ready"))
        XCTAssertFalse(app.descendants(matching: .any)["tuner.meter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.frequency"].exists)

        let retry = app.descendants(matching: .any)["microphone.retry"]
        if retry.waitForExistence(timeout: 3) {
            retry.tap()
        } else {
            XCTAssertTrue(captureStart.waitForExistence(timeout: 8))
            captureStart.tap()
        }
        XCTAssertTrue(captureStop.waitForExistence(timeout: 15), "Tuner must restart after the real timer interruption.")
        preservePhysicalScreenshot(named: "Physical Tuner recovered after on-device timer interruption")
        captureStop.tap()
    }

    @MainActor
    func testPhysicalReleaseTunerA440AcousticReference() throws {
        let app = launchPhysicalReleaseApp()
        openTab("Tuner", in: app)

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        allowMicrophonePermissionIfPresented()
        XCTAssertTrue(stop.waitForExistence(timeout: 15))

        let note = app.descendants(matching: .any)["tuner.note"]
        let signalState = app.staticTexts.matching(identifier: "tuner.signalState").firstMatch
        let waitStart = Date()
        NSLog("BRASSTUNE_ACOUSTIC_READY expectedConcertHz=440 expectedWrittenNote=B4")
        let writtenB4 = NSPredicate(format: "label CONTAINS %@", "B4")
        expectation(for: writtenB4, evaluatedWith: note)
        waitForExpectations(timeout: 35)
        let readyToWrittenNoteMilliseconds = Date().timeIntervalSince(waitStart) * 1_000

        let frequency = app.descendants(matching: .any)["tuner.frequency"]
        let cents = app.descendants(matching: .any)["tuner.cents"]
        let instrument = app.descendants(matching: .any)["tuner.instrument"]
        XCTAssertTrue(frequency.waitForExistence(timeout: 5))
        XCTAssertTrue(cents.exists)
        XCTAssertTrue(instrument.exists)
        XCTAssertTrue(signalState.label.contains("Signal locked"))
        XCTAssertTrue(instrument.label.contains("Trumpet in B♭"))

        func firstNumber(in value: String) -> Double? {
            value.split { !$0.isNumber && $0 != "." && $0 != "-" && $0 != "+" }
                .compactMap { Double($0) }
                .first
        }

        let observedFrequency = firstNumber(in: frequency.label)
        let observedCents = firstNumber(in: cents.label)
        XCTAssertNotNil(observedFrequency)
        XCTAssertNotNil(observedCents)
        if let observedFrequency {
            XCTAssertLessThanOrEqual(abs(observedFrequency - 440), 5)
        }
        if let observedCents {
            XCTAssertLessThanOrEqual(abs(observedCents), 10)
        }

        let measurement = XCTAttachment(string: """
        source=Mac built-in speaker, digitally generated 440 Hz reference
        selectedProfile=Trumpet in B-flat
        expectedWrittenNote=B4
        observedNote=\(note.label)
        observedFrequency=\(frequency.label)
        observedCents=\(cents.label)
        observedSignalState=\(signalState.label)
        readyMarkerToWrittenNoteMilliseconds=\(String(format: "%.1f", readyToWrittenNoteMilliseconds))
        limitation=Marker-to-note is host-orchestrated and the source onset is not on the XCTest clock; it is not calibrated acoustic latency.
        """)
        measurement.name = "Physical A440 acoustic Tuner observation"
        measurement.lifetime = .keepAlways
        add(measurement)
        preservePhysicalScreenshot(named: "Physical Tuner locked to Mac speaker A440")
        stop.tap()
    }

    /// Samples the real physical Tuner display against a continuous Mac-speaker
    /// A440 reference. The source is deliberately started before this test, so
    /// `steadySourceToStableLockMilliseconds` measures UI acquisition from an
    /// already-present steady tone, not calibrated acoustic onset latency.
    @MainActor
    func testPhysicalReleaseTunerSustainedA440DisplayStability() throws {
        let app = launchPhysicalReleaseApp(extraArguments: ["UITEST_TUNER_A440_STABILITY"])
        openTab("Tuner", in: app)

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        allowMicrophonePermissionIfPresented()
        XCTAssertTrue(stop.waitForExistence(timeout: 15))

        let readout = app.descendants(matching: .any)["tuner.readout"]
        let note = app.descendants(matching: .any)["tuner.note"]
        let frequency = app.descendants(matching: .any)["tuner.frequency"]
        let cents = app.descendants(matching: .any)["tuner.cents"]
        let signalState = app.staticTexts.matching(identifier: "tuner.signalState").firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: 5))

        NSLog("BRASSTUNE_A440_STABILITY_READY expectedConcertHz=440 expectedWrittenNote=B4 samples=40 intervalSeconds=0.5")
        let lockStart = Date()
        let stableB4 = NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS[c] %@",
            "B4",
            "In tune"
        )
        expectation(for: stableB4, evaluatedWith: readout)
        waitForExpectations(timeout: 20)
        let steadySourceToStableLockMilliseconds = Date().timeIntervalSince(lockStart) * 1_000

        func firstNumber(in value: String) -> Double? {
            value.split { !$0.isNumber && $0 != "." && $0 != "-" && $0 != "+" }
                .compactMap { Double($0) }
                .first
        }

        struct Sample {
            let index: Int
            let note: String
            let frequencyHz: Double?
            let cents: Double?
            let signal: String

            var isStableB4: Bool {
                note.contains("B4")
                    && signal.localizedCaseInsensitiveContains("Signal locked")
                    && frequencyHz.map { abs($0 - 440) <= 5 } == true
                    && cents.map { abs($0) <= 10 } == true
            }
        }

        var samples: [Sample] = []
        for index in 0..<40 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            samples.append(
                Sample(
                    index: index,
                    note: note.label,
                    frequencyHz: firstNumber(in: frequency.label),
                    cents: firstNumber(in: cents.label),
                    signal: signalState.label
                )
            )
        }

        let stableSamples = samples.filter(\.isStableB4)
        let measuredFrequencies = samples.compactMap(\.frequencyHz)
        let measuredCents = samples.compactMap(\.cents)
        XCTAssertGreaterThanOrEqual(
            stableSamples.count,
            32,
            "At least 80% of physical A440 display samples must remain locked, in tune, and within the declared frequency/cents tolerances."
        )
        XCTAssertEqual(measuredFrequencies.count, samples.count)
        XCTAssertEqual(measuredCents.count, samples.count)

        let rows = samples.map { sample in
            "\(sample.index),\(sample.note),\(sample.frequencyHz.map { String($0) } ?? "missing"),\(sample.cents.map { String($0) } ?? "missing"),\(sample.signal),\(sample.isStableB4)"
        }.joined(separator: "\n")
        let evidence = XCTAttachment(string: """
        source=Mac built-in speaker, continuous digitally generated 440 Hz sine
        selectedProfile=Trumpet in B-flat
        expectedWrittenNote=B4
        steadySourceToStableLockMilliseconds=\(String(format: "%.1f", steadySourceToStableLockMilliseconds))
        samplingIntervalMilliseconds=500
        sampleCount=\(samples.count)
        stableSampleCount=\(stableSamples.count)
        stableRatio=\(String(format: "%.3f", Double(stableSamples.count) / Double(samples.count)))
        frequencyRangeHz=\(measuredFrequencies.min().map { String($0) } ?? "missing")...\(measuredFrequencies.max().map { String($0) } ?? "missing")
        centsRange=\(measuredCents.min().map { String($0) } ?? "missing")...\(measuredCents.max().map { String($0) } ?? "missing")
        limitation=Mac speaker level, room, distance, and iPhone microphone processing are not calibrated; the tone predates capture, so this is stable-display acquisition and sustained-display evidence, not source-onset latency.
        index,note,frequencyHz,cents,signal,isStableB4
        \(rows)
        """)
        evidence.name = "Physical sustained A440 Tuner display stability"
        evidence.lifetime = .keepAlways
        add(evidence)
        preservePhysicalScreenshot(named: "Physical sustained A440 Tuner display stability completed")
        stop.tap()
    }

    /// Holds the real physical-device metronome at a fixed 120 BPM long enough
    /// for an independently clocked Mac microphone recording to measure audible
    /// inter-onset timing. The recording is started by the host only after this
    /// test product is installed and running; this test deliberately avoids any
    /// simulator-only timing seam.
    @MainActor
    func testPhysicalReleaseMetronomeSustained120BPM() throws {
        let app = launchPhysicalReleaseApp(extraArguments: ["UITEST_METRONOME_120_ACOUSTIC"])
        openTab("Practice", in: app)

        let metronome = app.descendants(matching: .any)["practice.metronome"]
        XCTAssertTrue(metronome.waitForExistence(timeout: 8))
        metronome.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))

        let bpm = app.descendants(matching: .any)["metronome.bpm"]
        XCTAssertTrue(bpm.waitForExistence(timeout: 5))
        XCTAssertTrue(bpm.label.contains("120"))

        let advanced = app.buttons["Advanced rhythm"]
        bringIntoView(advanced, in: app)
        advanced.tap()
        let accent = app.switches["metronome.accentFirstBeat"]
        bringIntoView(accent, in: app)
        XCTAssertTrue(accent.waitForExistence(timeout: 5))
        XCTAssertFalse(accent.isSelected)

        let visualOnly = app.switches["metronome.visualOnly"]
        let haptics = app.switches["metronome.haptics"]
        bringIntoView(visualOnly, in: app)
        XCTAssertTrue(visualOnly.waitForExistence(timeout: 5))
        XCTAssertTrue(haptics.exists)
        XCTAssertFalse(visualOnly.isSelected)
        XCTAssertFalse(haptics.isSelected)

        XCTAssertTrue(app.descendants(matching: .any)["metronome.volume"].exists)

        // Collapse the inspected disclosure before returning to the transport.
        // The generic helper only scrolls deeper into a screen, while the
        // metronome transport sits above these advanced controls.
        advanced.tap()

        let toggle = app.descendants(matching: .any)["metronome.toggle"]
        for _ in 0..<8 {
            if toggle.exists, toggle.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable, "The metronome transport must remain reachable after inspecting advanced rhythm controls.")
        NSLog("BRASSTUNE_METRONOME_ACOUSTIC_READY bpm=120 subdivision=quarter accent=off haptics=off visualOnly=off durationSeconds=180")
        toggle.tap()
        sleep(1)
        preservePhysicalScreenshot(named: "Physical sustained metronome 120 BPM started")

        sleep(180)

        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        sleep(1)
        preservePhysicalScreenshot(named: "Physical sustained metronome 120 BPM completed")
    }

    /// Opens the real system Photos picker on the connected iPhone, imports the
    /// preserved August 1 PNG screenshot, and proves the local copy survives an
    /// app termination/relaunch before exercising both delete outcomes. This is
    /// deliberately separate from fixture-backed score tests so a missing or
    /// inaccessible picker cannot be mistaken for a successful Photos import.
    @MainActor
    func testPhysicalReleasePhotosPickerProbe() throws {
        let app = launchPhysicalReleaseApp()
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 8))

        let photos = app.descendants(matching: .any)["score.import.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        photos.tap()
        sleep(3)

        preservePhysicalScreenshot(named: "Physical Photos picker before selection")
        print("PHYSICAL_PHOTOS_PICKER_PROBE_BEGIN")
        print(app.debugDescription)
        print("PHYSICAL_PHOTOS_PICKER_PROBE_END")

        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 8)
                || app.collectionViews.firstMatch.waitForExistence(timeout: 8),
            "The physical Photos picker must expose a navigable surface."
        )

        let preservedScreenshot = app.images.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@",
                "Screenshot",
                "August 01, 11:54"
            )
        ).firstMatch
        XCTAssertTrue(
            preservedScreenshot.waitForExistence(timeout: 8),
            "The known August 1 screenshot must remain available for a deterministic physical Photos import."
        )
        let pickerOnboardingClose = app.buttons["Close"].firstMatch
        if pickerOnboardingClose.exists {
            pickerOnboardingClose.tap()
            sleep(1)
        }
        // The physical picker reports the first cell at x = -0.0, which makes
        // XCUIElement.tap() synthesize the invalid hit point (-1, -1). Use the
        // visible cell center recorded above instead of treating that XCTest
        // coordinate-rounding defect as a Photos import failure.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.165, dy: 0.407)).tap()

        let scoreCard = app.descendants(matching: .any)["score.card"]
        XCTAssertTrue(scoreCard.waitForExistence(timeout: 20), "The selected physical PNG must import as a local score.")
        preservePhysicalScreenshot(named: "Physical Photos PNG imported as local score")

        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 8),
            "The physically imported Photos score must survive termination and relaunch."
        )

        let delete = app.descendants(matching: .any)["score.delete"]
        bringIntoView(delete, in: app)
        delete.tap()
        XCTAssertTrue(app.buttons["Delete local score"].waitForExistence(timeout: 5))
        app.buttons["Keep score"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.card"].exists)

        delete.tap()
        XCTAssertTrue(app.buttons["Delete local score"].waitForExistence(timeout: 5))
        app.buttons["Delete local score"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.empty"].waitForExistence(timeout: 8))
        preservePhysicalScreenshot(named: "Physical Photos score confirmed deleted")
    }

    /// Opens the real document picker, selects a known visible PNG without
    /// altering the source in iCloud Drive, and proves that BrassTune's local
    /// copy survives termination/relaunch before deleting only that copy.
    @MainActor
    func testPhysicalReleaseFilesPickerProbe() throws {
        let app = launchPhysicalReleaseApp()
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 8))

        let files = app.descendants(matching: .any)["score.import.files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        files.tap()
        sleep(3)

        preservePhysicalScreenshot(named: "Physical Files picker before selection")
        print("PHYSICAL_FILES_PICKER_PROBE_BEGIN")
        print(app.debugDescription)
        print("PHYSICAL_FILES_PICKER_PROBE_END")
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 8),
            "The physical Files importer must expose a navigable document-picker surface."
        )

        let knownPNG = app.cells.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Screenshot 2026-07-04 at 12.03.03")
        ).firstMatch
        XCTAssertTrue(knownPNG.waitForExistence(timeout: 8), "A deterministic compatible PNG must be visible in physical Files Recents.")
        knownPNG.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 20),
            "The selected physical Files PNG must import as a local score."
        )
        preservePhysicalScreenshot(named: "Physical Files PNG imported as local score")

        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["practice.sheetMusic"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.scorePractice"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["score.card"].waitForExistence(timeout: 8),
            "The physically imported Files score must survive termination and relaunch."
        )

        let delete = app.descendants(matching: .any)["score.delete"]
        bringIntoView(delete, in: app)
        delete.tap()
        XCTAssertTrue(app.buttons["Delete local score"].waitForExistence(timeout: 5))
        app.buttons["Delete local score"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["score.empty"].waitForExistence(timeout: 8))
        preservePhysicalScreenshot(named: "Physical Files score local copy deleted")
    }

    /// Strict structural audit. Contrast is deliberately excluded so a color
    /// detector false-positive cannot hide a real hit-region, trait, clipping,
    /// Dynamic Type, or description regression.
    @MainActor
    func testPhysicalReleaseAccessibilityAuditPrimaryTabsStrict() throws {
        defer { XCUIDevice.shared.appearance = .light }
        for (appearanceName, appearance) in [("Light", XCUIDevice.Appearance.light), ("Dark", .dark)] {
            let app = launchPhysicalAccessibilityAuditApp(appearance: appearance)
            let unexpected = try auditPrimaryTabs(
                in: app,
                appearanceName: appearanceName,
                auditTypes: [.elementDetection, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped, .trait]
            )
            XCTAssertTrue(unexpected.isEmpty, "Unexpected \(appearanceName) strict accessibility findings:\n\(unexpected.joined(separator: "\n"))")
            app.terminate()
        }
    }

    /// Contrast remains a release gate in both appearances. Any finding is
    /// retained in the attachment and fails the run; it is never allowlisted.
    @MainActor
    func testPhysicalReleaseAccessibilityContrastEvidencePrimaryTabs() throws {
        defer { XCUIDevice.shared.appearance = .light }
        var allUnexpected: [String] = []
        for (appearanceName, appearance) in [("Light", XCUIDevice.Appearance.light), ("Dark", .dark)] {
            let app = launchPhysicalAccessibilityAuditApp(appearance: appearance)
            let unexpected = try auditPrimaryTabs(
                in: app,
                appearanceName: appearanceName,
                auditTypes: .contrast
            )
            allUnexpected.append(contentsOf: unexpected)
            app.terminate()
        }
        XCTAssertTrue(
            allUnexpected.isEmpty,
            "Unexpected physical contrast findings:\n\(allUnexpected.joined(separator: "\n"))"
        )
    }

    @MainActor
    private func launchPhysicalAccessibilityAuditApp(appearance: XCUIDevice.Appearance) -> XCUIApplication {
        XCUIDevice.shared.appearance = appearance
        return launchPhysicalReleaseApp()
    }

    @MainActor
    private func auditPrimaryTabs(
        in app: XCUIApplication,
        appearanceName: String,
        auditTypes: XCUIAccessibilityAuditType
    ) throws -> [String] {
        var unexpected: [String] = []
        let tabs: [(title: String, screenIdentifier: String)] = [
            ("Practice", "screen.practice"),
            ("Tuner", "screen.tuner"),
            ("Scales", "screen.scales"),
            ("Progress", "screen.progress"),
            ("More", "screen.more"),
        ]
        for tab in tabs {
            let title = tab.title
            openTab(title, in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)[tab.screenIdentifier].waitForExistence(timeout: 8),
                "Accessibility audit must reach the intended \(title) surface before auditing."
            )
            preservePhysicalScreenshot(named: "Physical accessibility \(appearanceName) \(title) tab")
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                let finding = "appearance=\(appearanceName) tab=\(title) \(String(describing: issue))"
                unexpected.append(finding)
                print("PHYSICAL_ACCESSIBILITY_AUDIT_UNEXPECTED \(finding)")
                return true
            }
        }
        let evidence = XCTAttachment(string: """
        appearance=\(appearanceName)
        auditTypes=\(auditTypes.rawValue)
        unexpected=\(unexpected.isEmpty ? "none" : unexpected.joined(separator: "\n"))
        """)
        evidence.name = "Physical \(appearanceName) accessibility audit evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
        return unexpected
    }

    @MainActor
    func testPhysicalReleaseTunerLowMidHighAcousticReferences() throws {
        let app = launchPhysicalReleaseApp()
        openTab("Tuner", in: app)

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        allowMicrophonePermissionIfPresented()
        XCTAssertTrue(stop.waitForExistence(timeout: 15))

        struct AcousticCase {
            let id: String
            let soundingFrequencyHz: Double
            let expectedWrittenNote: String
        }
        let cases = [
            AcousticCase(id: "representative-low", soundingFrequencyHz: 261.625565, expectedWrittenNote: "D4"),
            AcousticCase(id: "middle", soundingFrequencyHz: 440.0, expectedWrittenNote: "B4"),
            AcousticCase(id: "representative-high", soundingFrequencyHz: 783.990872, expectedWrittenNote: "A5"),
        ]
        let readout = app.descendants(matching: .any)["tuner.readout"]
        let frequency = app.descendants(matching: .any)["tuner.frequency"]
        let cents = app.descendants(matching: .any)["tuner.cents"]
        NSLog("BRASSTUNE_ACOUSTIC_SEQUENCE_READY profile=trumpet cases=3")

        func firstNumber(in value: String) -> Double? {
            value.split { !$0.isNumber && $0 != "." && $0 != "-" && $0 != "+" }
                .compactMap { Double($0) }
                .first
        }

        for acousticCase in cases {
            let lockedExpectedNote = NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS[c] %@",
                acousticCase.expectedWrittenNote,
                "In tune"
            )
            expectation(for: lockedExpectedNote, evaluatedWith: readout)
            waitForExpectations(timeout: 45)
            XCTAssertTrue(frequency.waitForExistence(timeout: 5))
            XCTAssertTrue(cents.exists)
            let observedFrequency = firstNumber(in: frequency.label)
            let observedCents = firstNumber(in: cents.label)
            XCTAssertNotNil(observedFrequency)
            XCTAssertNotNil(observedCents)
            if let observedFrequency {
                XCTAssertLessThanOrEqual(abs(observedFrequency - acousticCase.soundingFrequencyHz), 6)
            }
            if let observedCents {
                XCTAssertLessThanOrEqual(abs(observedCents), 10)
            }

            let observation = XCTAttachment(string: """
            case=\(acousticCase.id)
            source=Mac built-in speaker, digitally generated steady sine
            selectedProfile=Trumpet in B-flat
            expectedSoundingFrequencyHz=\(acousticCase.soundingFrequencyHz)
            expectedWrittenNote=\(acousticCase.expectedWrittenNote)
            observedReadout=\(readout.label)
            observedFrequency=\(frequency.label)
            observedCents=\(cents.label)
            limitation=Built-in speaker level, room, distance, and microphone processing are not calibrated.
            """)
            observation.name = "Physical Tuner \(acousticCase.id) acoustic observation"
            observation.lifetime = .keepAlways
            add(observation)
            preservePhysicalScreenshot(named: "Physical Tuner \(acousticCase.id) acoustic lock")
        }
        stop.tap()
    }

    /// Exercises the real operating-system permission transition on the isolated
    /// `.dev` bundle. The caller must uninstall only that bundle before this test
    /// so iOS presents a fresh microphone prompt; production TestFlight state is
    /// deliberately outside this test's scope.
    @MainActor
    func testPhysicalReleaseMicrophoneDenyGrantRecovery() throws {
        let app = launchPhysicalReleaseApp()
        openTab("Tuner", in: app)

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        denyMicrophonePermission()

        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        let deniedPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Microphone access is off")
        expectation(for: deniedPredicate, evaluatedWith: readout)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(readout.label.contains("Ready"))
        XCTAssertFalse(app.descendants(matching: .any)["tuner.meter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.frequency"].exists)
        preservePhysicalScreenshot(named: "Physical microphone denied recovery state")

        let openSettings = app.descendants(matching: .any)["microphone.openSettings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        // Changing a privacy switch can terminate the target app. If iOS does
        // that, relaunch without the one-shot reset arguments so the real guest
        // and denied-state persistence are not erased by the test harness.
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        openSettings.tap()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
        let microphoneSwitch = settings.switches.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Microphone")
        ).firstMatch
        XCTAssertTrue(
            microphoneSwitch.waitForExistence(timeout: 8),
            "The BrassTune.dev app-settings page must expose the Microphone permission switch."
        )
        let switchValue = (microphoneSwitch.value as? String)?.lowercased() ?? "unknown"
        if switchValue == "0" || switchValue == "off" {
            let nestedToggle = microphoneSwitch.descendants(matching: .switch).firstMatch
            if nestedToggle.exists {
                nestedToggle.tap()
            } else {
                // iOS 26 exposes the labelled Settings row as the switch element
                // while the hittable toggle occupies the trailing edge of that row.
                microphoneSwitch.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.90, dy: 0.50)
                ).tap()
            }
        } else if switchValue == "unknown", !microphoneSwitch.isSelected {
            microphoneSwitch.coordinate(
                withNormalizedOffset: CGVector(dx: 0.90, dy: 0.50)
            ).tap()
        }
        let enabledPredicate = NSPredicate(
            format: "value == %@ OR value == %@ OR value == %@",
            "1",
            "on",
            true as NSNumber
        )
        expectation(for: enabledPredicate, evaluatedWith: microphoneSwitch)
        waitForExpectations(timeout: 5)
        preservePhysicalScreenshot(named: "Physical microphone permission enabled in iOS Settings")

        settings.terminate()
        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        if app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 3) {
            app.descendants(matching: .any)["gateway.continueAsGuest"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 8))
            app.descendants(matching: .any)["onboarding.startPractice"].tap()
        }
        if app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 3) {
            openTab("Tuner", in: app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        let retry = app.descendants(matching: .any)["microphone.retry"]
        let restart = app.descendants(matching: .any)["tuner.recordButton"]
        if retry.waitForExistence(timeout: 3) {
            retry.tap()
        } else {
            XCTAssertTrue(
                restart.waitForExistence(timeout: 5),
                "After the Settings grant, Tuner must expose either Retry or its real capture start control."
            )
            restart.tap()
        }

        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "Tuner must recover after microphone permission is enabled.")
        XCTAssertFalse(readout.label.contains("Ready"))
        preservePhysicalScreenshot(named: "Physical tuner recovered after permission grant")
        stop.tap()
    }

    /// Real-device-only closure test. The compile condition is supplied only by the
    /// owner-controlled physical release command, so ordinary simulator and CI UI
    /// suites never request microphone permission or emit audible test tones.
    @MainActor
    func testPhysicalReleaseAudioCrashFamilyStress() throws {
        let app = launchPhysicalReleaseApp()

        openTab("Tuner", in: app)
        let tunerStart = app.descendants(matching: .any)["tuner.recordButton"]
        let tunerStop = app.descendants(matching: .any)["tuner.floating.stop"]
        let tunerRetry = app.descendants(matching: .any)["microphone.retry"]
        let tunerReadout = app.descendants(matching: .any)["tuner.readout"]
        for cycle in 0..<20 {
            var started = false
            for attempt in 0..<3 {
                if tunerRetry.exists {
                    XCTAssertFalse(
                        tunerReadout.label.contains("Ready"),
                        "An interrupted physical capture must not fabricate the Ready state."
                    )
                    tunerRetry.tap()
                } else {
                    XCTAssertTrue(tunerStart.waitForExistence(timeout: 8), "Tuner start missing on cycle \(cycle + 1)")
                    tunerStart.tap()
                    if cycle == 0, attempt == 0 {
                        allowMicrophonePermissionIfPresented()
                    }
                }

                if tunerStop.waitForExistence(timeout: 12) {
                    started = true
                    break
                }

                XCTAssertTrue(
                    tunerRetry.waitForExistence(timeout: 3) || tunerStart.exists,
                    "Live tuner neither started nor exposed a recoverable state on cycle \(cycle + 1), attempt \(attempt + 1)."
                )
            }
            XCTAssertTrue(started, "Live tuner did not recover and start on cycle \(cycle + 1)")
            guard started else { return }
            XCTAssertFalse(
                tunerReadout.label.contains("Ready"),
                "An active physical capture must not retain the idle Ready state."
            )
            tunerStop.tap()
        }

        XCTAssertTrue(tunerStart.waitForExistence(timeout: 8))
        tunerStart.tap()
        XCTAssertTrue(tunerStop.waitForExistence(timeout: 12))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        XCTAssertFalse(tunerStop.exists, "Backgrounding must tear down the live input tap.")

        openTab("Scales", in: app)
        let scaleStart = app.descendants(matching: .any)["scales.start"]
        let scaleStop = app.descendants(matching: .any)["playAlong.stop"]
        for cycle in 0..<20 {
            XCTAssertTrue(scaleStart.waitForExistence(timeout: 8), "Scale start missing on cycle \(cycle + 1)")
            scaleStart.tap()
            XCTAssertTrue(scaleStop.waitForExistence(timeout: 12), "Mic-assisted scale did not start on cycle \(cycle + 1)")
            scaleStop.tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.scales"].waitForExistence(timeout: 8))
        }

        openTab("Practice", in: app)
        app.descendants(matching: .any)["practice.metronome"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        let metronomeToggle = app.descendants(matching: .any)["metronome.toggle"]
        for _ in 0..<20 {
            metronomeToggle.tap()
            metronomeToggle.tap()
        }
        metronomeToggle.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        XCTAssertTrue(metronomeToggle.isHittable)
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["practice.drone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))
        for cycle in 0..<20 {
            let playTone = app.buttons["Play reference tone"]
            XCTAssertTrue(playTone.waitForExistence(timeout: 8), "Reference tone start missing on cycle \(cycle + 1)")
            playTone.tap()
            let stopTone = app.buttons["Stop reference tone"]
            XCTAssertTrue(stopTone.waitForExistence(timeout: 8), "Reference tone did not start on cycle \(cycle + 1)")
            stopTone.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))

        for _ in 0..<10 {
            for title in ["Practice", "Tuner", "Scales", "Progress", "More"] {
                openTab(title, in: app)
            }
        }
        openTab("Practice", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
    }

    /// Coordinates with the host-side physical release harness, which restarts
    /// iOS audio services only after the live capture marker is emitted. This
    /// keeps the destructive system action outside the app while proving that
    /// the real notification tears down stale capture state and that subsequent
    /// microphone and output graphs are rebuilt successfully.
    @MainActor
    func testPhysicalReleaseMediaServicesResetAndRecovery() throws {
        let app = launchPhysicalReleaseApp()

        openTab("Tuner", in: app)
        let captureStart = app.descendants(matching: .any)["tuner.recordButton"]
        let captureStop = app.descendants(matching: .any)["tuner.floating.stop"]
        let captureRetry = app.descendants(matching: .any)["microphone.retry"]
        let readout = app.descendants(matching: .any)["tuner.readout"]
        XCTAssertTrue(captureStart.waitForExistence(timeout: 8))
        captureStart.tap()
        allowMicrophonePermissionIfPresented()
        XCTAssertTrue(captureStop.waitForExistence(timeout: 15))
        preservePhysicalScreenshot(named: "Physical Tuner before media-services reset")

        NSLog("PHYSICAL_MEDIA_SERVICES_RESET_READY")
        let resetDeadline = Date().addingTimeInterval(30)
        while Date() < resetDeadline, captureStop.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTAssertFalse(captureStop.exists, "A real media-services reset must tear down the stale live input graph.")
        XCTAssertTrue(readout.waitForExistence(timeout: 5))
        XCTAssertFalse(readout.label.contains("Ready"), "A media-services reset must not fabricate a Ready measurement state.")
        XCTAssertFalse(app.descendants(matching: .any)["tuner.meter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.cents"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.frequency"].exists)
        preservePhysicalScreenshot(named: "Physical Tuner recovered state after media-services reset")

        if captureRetry.waitForExistence(timeout: 5) {
            captureRetry.tap()
        } else {
            XCTAssertTrue(captureStart.waitForExistence(timeout: 8))
            captureStart.tap()
        }
        XCTAssertTrue(captureStop.waitForExistence(timeout: 15), "Tuner must start on a fresh input graph after media services recover.")
        captureStop.tap()

        openTab("Practice", in: app)
        app.descendants(matching: .any)["practice.drone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 8))
        let playTone = app.buttons["Play reference tone"]
        XCTAssertTrue(playTone.waitForExistence(timeout: 8))
        playTone.tap()
        let stopTone = app.buttons["Stop reference tone"]
        XCTAssertTrue(stopTone.waitForExistence(timeout: 12), "Reference tone must use a fresh output graph after reset.")
        stopTone.tap()

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["practice.metronome"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 8))
        let metronomeToggle = app.descendants(matching: .any)["metronome.toggle"]
        XCTAssertTrue(metronomeToggle.waitForExistence(timeout: 8))
        metronomeToggle.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(metronomeToggle.isHittable)
        metronomeToggle.tap()
        preservePhysicalScreenshot(named: "Physical audio features restarted after media-services reset")
    }

    /// Verifies live production provider discovery in an isolated `.dev`
    /// launch that cannot read, refresh, save, or delete a real credential.
    @MainActor
    func testPhysicalReleaseAuthStateAndLiveProviderConfiguration() throws {
        assertPhysicalDevProbeEnvironment()
        let providerApp = physicalDevApplication()
        providerApp.launchArguments = ["UITEST_FORCE_AUTH_GATEWAY", "UITEST_AUTH_EMPTY", "UITEST_AUTH_NO_PERSIST"]
        providerApp.launch()
        XCTAssertTrue(providerApp.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        let createAccount = providerApp.descendants(matching: .any)["gateway.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
        createAccount.tap()

        XCTAssertTrue(
            providerApp.descendants(matching: .any)["gateway.authAppleSignIn"].waitForExistence(timeout: 12),
            "Production provider discovery must expose native Apple sign-in on the physical `.dev` build."
        )
        XCTAssertTrue(
            providerApp.descendants(matching: .any)["gateway.authGoogleSignIn"].waitForExistence(timeout: 12),
            "Production provider discovery must expose Google sign-in on the physical `.dev` build."
        )
    }

    /// Opens the real Google OAuth surface but deliberately stops before an
    /// account is selected. Account selection is a separate sensitive-data
    /// transmission boundary and is never automated by this probe.
    @MainActor
    func testPhysicalReleaseGoogleConsentSurfaceProbe() throws {
        assertPhysicalDevProbeEnvironment()
        let app = launchPhysicalLiveAuthGateway()
        let google = app.descendants(matching: .any)["gateway.authGoogleSignIn"]
        XCTAssertTrue(google.waitForExistence(timeout: 12))
        google.tap()
        XCTAssertTrue(
            waitForGoogleConsentSurface(in: app),
            "Google sign-in must present the system web-authentication consent alert."
        )
        app.terminate()
    }

    /// Opens the real native Apple authorization surface but deliberately
    /// stops before Continue or biometric authorization. No screenshot is
    /// retained because the system sheet can display private account data.
    @MainActor
    func testPhysicalReleaseAppleConsentSurfaceProbe() throws {
        assertPhysicalDevProbeEnvironment()
        let app = launchPhysicalLiveAuthGateway()
        let apple = app.descendants(matching: .any)["gateway.authAppleSignIn"]
        XCTAssertTrue(apple.waitForExistence(timeout: 12))
        apple.tap()
        XCTAssertTrue(
            waitForAppleAuthorizationSurface(),
            "Apple sign-in must present the native AuthKit authorization sheet."
        )
        app.terminate()
    }

    /// Confirms the normal physical `.dev` app is safely signed out before an
    /// opt-in provider journey is permitted to start.
    @MainActor
    func testPhysicalNormalDevSignedOutPreflight() throws {
        assertPhysicalDevProbeEnvironment()
        let app = launchNormalPhysicalDevApp()
        reachSettingsFromNormalDevLaunch(in: app)
        XCTAssertFalse(app.descendants(matching: .any)["settings.signOut"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.createAccount"].waitForExistence(timeout: 8))
    }

    /// Signs out only the physical `.dev` session created by an immediately
    /// preceding authorized live-auth run. This is inert unless the private
    /// physical runner opts in explicitly.
    @MainActor
    func testPhysicalLiveAuthorizedSessionCleanup() throws {
        guard runtimeConfigurationValue(named: "LIVE_AUTH_CLEANUP_AUTHORIZED_SESSION") == "YES" else {
            throw XCTSkip("Authorized live-auth session cleanup is disabled.")
        }
        assertPhysicalDevProbeEnvironment()

        let app = launchNormalPhysicalDevApp()
        reachSettingsFromNormalDevLaunch(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOut"].waitForExistence(timeout: 8))
        signOutAndAssertColdRelaunchIsSignedOut(in: app)
    }

    /// This opt-in journey is intentionally inert without a digest supplied by
    /// the physical test scheme. It does not save screenshots or attachments.
    @MainActor
    func testPhysicalLiveGoogleAuthenticationRestoresAndSignsOut() throws {
        let accountDigest = try requiredLiveAuthAccountDigest(for: .google)
        let allowFirstVisibleAccount = liveAuthAllowsFirstVisibleAccount(for: .google)
        assertPhysicalDevProbeEnvironment()

        let app = launchNormalPhysicalDevApp()
        defer { terminatePrivateLiveAuthSurfaces(in: app) }
        let google = try openLiveAuthForm(in: app, provider: .google)
        google.tap()
        guard waitForGoogleConsentSurface(in: app) else {
            throw XCTSkip("Google authorization surface was unavailable for this private physical run.")
        }

        guard let continueButton = googleConsentContinueButton(in: app) else {
            throw XCTSkip("Google authorization could not continue in this private physical run.")
        }
        continueButton.tap()

        guard let account = authorizedAccountElement(
            applications: { self.googleAuthorizationApplications(in: app) },
            expectedDigest: accountDigest,
            allowFirstVisibleAccount: allowFirstVisibleAccount,
            timeout: 15
        ) else {
            throw XCTSkip("No authorized Google account was selected in this private physical run.")
        }
        guard account.waitForExistence(timeout: 3), account.isHittable else {
            terminateSensitiveProviderSurfaces()
            throw XCTSkip("Authorized Google account could not be selected in this private physical run.")
        }
        account.tap()
        completeOptionalGoogleProviderConsent()
        guard waitForGoogleCallbackOrGuestChoice(in: app) else {
            if googleSystemAuthorizationApplications().contains(where: { $0.state == .runningForeground }) {
                terminateSensitiveProviderSurfaces()
                throw XCTSkip("Google authorization remains open in this private physical run.")
            }
            preparePostProviderFailureSurface(in: app)
            XCTFail("Google callback did not complete after provider authorization closed.")
            return
        }
        chooseKeepPracticeSeparateIfPrompted(in: app)
        dismissSuccessfulAuthFormIfPresented(in: app)

        assertLiveSignedInState(in: app)
        coldRelaunch(app)
        assertLiveSignedInState(in: app)
        signOutAndAssertColdRelaunchIsSignedOut(in: app)
    }

    /// An attended physical run may present Apple's passcode handoff, but
    /// XCTest never reads or enters credential content.
    @MainActor
    func testPhysicalLiveAppleAuthenticationRestoresAndSignsOut() throws {
        guard liveAuthAllowsManualApplePasscodeEntry() else {
            throw XCTSkip("Live Apple authentication requires an explicitly attended private run.")
        }
        assertPhysicalDevProbeEnvironment()

        let app = launchNormalPhysicalDevApp()
        defer { terminatePrivateLiveAuthSurfaces(in: app) }
        let apple = try openLiveAuthForm(in: app, provider: .apple)
        apple.tap()
        guard let authorizationAction = waitForAppleAuthorizationAction() else {
            throw XCTSkip("Apple authorization surface was unavailable for this private physical run.")
        }
        let authKit = XCUIApplication(bundleIdentifier: "com.apple.AuthKitUIService")
        guard authorizationAction.waitForExistence(timeout: 5), authorizationAction.isHittable else {
            terminateSensitiveProviderSurfaces()
            throw XCTSkip("Apple authorization could not continue in this private physical run.")
        }
        authorizationAction.tap()
        guard waitForAppleCallbackOrGuestChoice(
            in: app,
            authKit: authKit,
            timeout: 120,
            allowProviderSurfaceEnd: true
        ) else {
            // Best-effort, runtime-unverified classification: only a physical
            // run can distinguish a pending biometric or passcode gate here.
            if authKit.state == .runningForeground, !authKit.buttons["Continue"].exists {
                terminateSensitiveProviderSurfaces()
                throw XCTSkip("Apple authorization is awaiting physical biometric or passcode completion.")
            }
            if authKit.state == .runningForeground {
                terminateSensitiveProviderSurfaces()
                throw XCTSkip("Apple authorization remains open in this private physical run.")
            }
            preparePostProviderFailureSurface(in: app)
            XCTFail("Apple callback did not complete after provider authorization closed.")
            return
        }
        chooseKeepPracticeSeparateIfPrompted(in: app)
        dismissSuccessfulAuthFormIfPresented(in: app)

        assertLiveSignedInState(in: app)
        coldRelaunch(app)
        assertLiveSignedInState(in: app)
        signOutAndAssertColdRelaunchIsSignedOut(in: app)
    }

    @MainActor
    private func launchPhysicalLiveAuthGateway() -> XCUIApplication {
        let app = physicalDevApplication()
        app.launchArguments = ["UITEST_FORCE_AUTH_GATEWAY", "UITEST_AUTH_EMPTY", "UITEST_AUTH_NO_PERSIST"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        let createAccount = app.descendants(matching: .any)["gateway.createAccount"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
        createAccount.tap()
        return app
    }

    private enum LiveAuthProvider: String {
        case google
        case apple

        var gatewayIdentifier: String {
            switch self {
            case .google: "gateway.authGoogleSignIn"
            case .apple: "gateway.authAppleSignIn"
            }
        }

        var digestConfigurationKey: String {
            "LIVE_AUTH_\(rawValue.uppercased())_ACCOUNT_LABEL_SHA256"
        }

        var firstVisibleAccountConfigurationKey: String {
            "LIVE_AUTH_\(rawValue.uppercased())_SELECT_FIRST_VISIBLE_ACCOUNT"
        }
    }

    @MainActor
    private func launchNormalPhysicalDevApp() -> XCUIApplication {
        let app = physicalDevApplication()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        return app
    }

    @MainActor
    private func reachSettingsFromNormalDevLaunch(in app: XCUIApplication) {
        let gateway = app.descendants(matching: .any)["screen.gateway"]
        if gateway.waitForExistence(timeout: 8) {
            let continueAsGuest = app.descendants(matching: .any)["gateway.continueAsGuest"]
            XCTAssertTrue(continueAsGuest.waitForExistence(timeout: 5))
            continueAsGuest.tap()
        }
        dismissOnboardingIfPresented(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        openTab("More", in: app)
        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openLiveAuthForm(in app: XCUIApplication, provider: LiveAuthProvider) throws -> XCUIElement {
        let gateway = app.descendants(matching: .any)["screen.gateway"]
        if gateway.waitForExistence(timeout: 8) {
            let createAccount = app.descendants(matching: .any)["gateway.createAccount"]
            XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
            createAccount.tap()
        } else {
            reachSettingsFromNormalDevLaunch(in: app)

            let signOut = app.descendants(matching: .any)["settings.signOut"]
            if signOut.exists {
                throw XCTSkip("Live authentication requires a signed-out normal `.dev` preflight.")
            }

            let createAccount = app.descendants(matching: .any)["settings.createAccount"]
            XCTAssertTrue(createAccount.waitForExistence(timeout: 8))
            createAccount.tap()
        }

        let providerButton = app.descendants(matching: .any)[provider.gatewayIdentifier]
        XCTAssertTrue(providerButton.waitForExistence(timeout: 12))
        return providerButton
    }

    private func requiredLiveAuthAccountDigest(for provider: LiveAuthProvider) throws -> String {
        let key = provider.digestConfigurationKey
        guard let value = runtimeConfigurationValue(named: key) else {
            throw XCTSkip("Live \(provider.rawValue) authentication is disabled without \(key).")
        }
        let digest = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw XCTSkip("Live \(provider.rawValue) authentication requires a SHA-256 digest configuration value.")
        }
        return digest
    }

    private func runtimeConfigurationValue(named key: String) -> String? {
        if let environmentValue = ProcessInfo.processInfo.environment[key], !environmentValue.isEmpty {
            return environmentValue
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-\(key)"), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1]
        return value.isEmpty ? nil : value
    }

    private func liveAuthAllowsFirstVisibleAccount(for provider: LiveAuthProvider) -> Bool {
        runtimeConfigurationValue(named: provider.firstVisibleAccountConfigurationKey) == "YES"
    }

    private func liveAuthAllowsManualApplePasscodeEntry() -> Bool {
        ProcessInfo.processInfo.environment["LIVE_AUTH_APPLE_ALLOW_MANUAL_PASSCODE_ENTRY"] == "YES"
    }

    @MainActor
    private func googleConsentContinueButton(in app: XCUIApplication) -> XCUIElement? {
        for candidate in googleAuthorizationApplications(in: app).map(\.alerts.firstMatch) {
            if isGoogleWebAuthenticationConsentAlert(candidate, timeout: 3) {
                return candidate.buttons["Continue"]
            }
        }
        return nil
    }

    @MainActor
    private func googleAuthorizationApplications(in app: XCUIApplication) -> [XCUIApplication] {
        ([app, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
            + googleSystemAuthorizationApplications())
            .filter { $0.state == .runningForeground }
    }

    @MainActor
    private func googleSystemAuthorizationApplications() -> [XCUIApplication] {
        [
            XCUIApplication(bundleIdentifier: "com.apple.SafariViewService"),
            XCUIApplication(bundleIdentifier: "com.apple.AuthenticationServicesUI"),
            XCUIApplication(bundleIdentifier: "com.apple.AuthenticationServicesAgent"),
            XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        ]
    }

    @MainActor
    private func terminatePrivateLiveAuthSurfaces(in app: XCUIApplication) {
        terminateSensitiveProviderSurfaces()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    @MainActor
    private func terminateSensitiveProviderSurfaces() {
        for application in googleSystemAuthorizationApplications()
            + [XCUIApplication(bundleIdentifier: "com.apple.AuthKitUIService")] where application.state == .runningForeground {
            application.terminate()
        }
    }

    @MainActor
    private func completeOptionalGoogleProviderConsent() {
        let deadline = Date().addingTimeInterval(6)
        repeat {
            for application in googleSystemAuthorizationApplications()
                where application.state == .runningForeground {
                for title in ["Continue", "Allow"] {
                    let control = application.buttons[title]
                    if control.exists {
                        if control.isHittable {
                            control.tap()
                            return
                        }
                        application.swipeUp()
                        break
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
    }

    @MainActor
    private func waitForGoogleCallbackOrGuestChoice(in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if app.buttons["Keep practice separate"].exists
                || app.descendants(matching: .any)["settings.signOut"].exists
                || app.descendants(matching: .any)["gateway.authNotice"].exists
                || app.descendants(matching: .any)["screen.instrumentSetup"].exists {
                return true
            }
            let providerSurfaceEnded = !app.descendants(matching: .any)["gateway.authGoogleSignIn"].exists
                && !app.descendants(matching: .any)["settings.googleSignIn"].exists
            if providerSurfaceEnded
                && googleSystemAuthorizationApplications().allSatisfy({ $0.state != .runningForeground }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func waitForAppleCallbackOrGuestChoice(
        in app: XCUIApplication,
        authKit: XCUIApplication,
        timeout: TimeInterval = 15,
        allowProviderSurfaceEnd: Bool = true
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.buttons["Keep practice separate"].exists
                || app.descendants(matching: .any)["settings.signOut"].exists
                || app.descendants(matching: .any)["gateway.authNotice"].exists
                || app.descendants(matching: .any)["screen.instrumentSetup"].exists {
                return true
            }
            if allowProviderSurfaceEnd {
                let providerSurfaceEnded = !app.descendants(matching: .any)["gateway.authAppleSignIn"].exists
                    && !app.descendants(matching: .any)["settings.appleSignIn"].exists
                if providerSurfaceEnded, authKit.state != .runningForeground {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func authorizedAccountElement(
        applications: () -> [XCUIApplication],
        expectedDigest: String,
        allowFirstVisibleAccount: Bool = false,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for application in applications() where application.state == .runningForeground {
                for element in accountLabelCandidates(in: application) where element.exists {
                    if allowFirstVisibleAccount
                        || accountLabelDigestMatches(element.label, expectedDigest: expectedDigest) {
                        return element
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func dismissSuccessfulAuthFormIfPresented(in app: XCUIApplication) {
        let notice = app.descendants(matching: .any)["gateway.authNotice"]
        guard notice.exists, notice.label.hasPrefix("Signed in.") else { return }
        let dismiss = app.buttons["Not now"]
        if dismiss.waitForExistence(timeout: 5), dismiss.isHittable {
            dismiss.tap()
        }
    }

    @MainActor
    private func accountLabelCandidates(in application: XCUIApplication) -> [XCUIElement] {
        let emailLikeLabel = NSPredicate(format: "label CONTAINS[c] %@", "@")
        let queries: [XCUIElementQuery] = [
            application.descendants(matching: .link).matching(emailLikeLabel),
            application.descendants(matching: .button).matching(emailLikeLabel),
            application.descendants(matching: .cell).matching(emailLikeLabel),
            application.descendants(matching: .staticText).matching(emailLikeLabel)
        ]
        return queries.flatMap(\.allElementsBoundByIndex)
    }

    private func accountLabelDigestMatches(_ label: String, expectedDigest: String) -> Bool {
        accountLabelDigestCandidates(label).contains { sha256AccountLabel($0) == expectedDigest }
    }

    private func accountLabelDigestCandidates(_ label: String) -> [String] {
        let normalized = normalizeAccountLabel(label)
        var candidates = [normalized]
        candidates += normalized.components(separatedBy: .newlines)
        candidates += normalized.components(separatedBy: .whitespacesAndNewlines)
        candidates += emailLikeSubstrings(in: normalized)
        return candidates.filter { !$0.isEmpty }
    }

    private func normalizeAccountLabel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private func emailLikeSubstrings(in value: String) -> [String] {
        let pattern = "[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private func sha256AccountLabel(_ label: String) -> String {
        let normalized = normalizeAccountLabel(label)
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    @MainActor
    private func chooseKeepPracticeSeparateIfPrompted(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(8)
        repeat {
            for application in [app, springboard] {
                let choice = application.buttons["Keep practice separate"]
                if choice.exists, choice.isHittable {
                    choice.tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
    }

    @MainActor
    private func assertLiveSignedInState(in app: XCUIApplication) {
        guard liveSignedInStateIsAvailable(in: app) else {
            preparePostProviderFailureSurface(in: app)
            XCTFail("Live authentication did not reach a generic signed-in state.")
            return
        }
    }

    @MainActor
    private func coldRelaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
    }

    @MainActor
    private func signOutAndAssertColdRelaunchIsSignedOut(in app: XCUIApplication) {
        let signOut = app.descendants(matching: .any)["settings.signOut"]
        guard signOut.waitForExistence(timeout: 5), signOut.isHittable else {
            preparePostProviderFailureSurface(in: app)
            XCTFail("Live authentication could not reach a generic sign-out control.")
            return
        }
        signOut.tap()
        guard liveSignedOutStateIsAvailable(in: app) else {
            preparePostProviderFailureSurface(in: app)
            XCTFail("Live authentication sign-out did not reach a generic signed-out state.")
            return
        }

        coldRelaunch(app)
        guard liveSignedOutStateIsAvailable(in: app) else {
            preparePostProviderFailureSurface(in: app)
            XCTFail("Live authentication cold-relaunch sign-out did not reach a generic signed-out state.")
            return
        }
    }

    @MainActor
    private func preparePostProviderFailureSurface(in app: XCUIApplication) {
        terminateSensitiveProviderSurfaces()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        app.activate()
    }

    @MainActor
    private func liveSignedInStateIsAvailable(in app: XCUIApplication) -> Bool {
        // Account entry from More -> Settings returns to Settings when the
        // authentication sheet closes. Recognize that valid signed-in state
        // directly instead of requiring a round trip through Practice first.
        if app.descendants(matching: .any)["screen.settings"].exists {
            return app.descendants(matching: .any)["settings.signOut"].waitForExistence(timeout: 12)
        }
        let startPractice = app.descendants(matching: .any)["onboarding.startPractice"]
        if startPractice.waitForExistence(timeout: 3), startPractice.isHittable {
            startPractice.tap()
        }
        guard app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8) else { return false }
        let more = primaryTab("More", in: app)
        guard more.waitForExistence(timeout: 5), more.isHittable else { return false }
        more.tap()
        let settings = app.descendants(matching: .any)["more.settings"]
        guard settings.waitForExistence(timeout: 5), settings.isHittable else { return false }
        settings.tap()
        return app.descendants(matching: .any)["settings.signOut"].waitForExistence(timeout: 12)
    }

    @MainActor
    private func liveSignedOutStateIsAvailable(in app: XCUIApplication) -> Bool {
        let gateway = app.descendants(matching: .any)["screen.gateway"]
        if gateway.waitForExistence(timeout: 8) {
            return app.descendants(matching: .any)["gateway.createAccount"].exists
                || app.descendants(matching: .any)["gateway.signIn"].exists
        }
        if app.descendants(matching: .any)["screen.settings"].exists {
            return app.descendants(matching: .any)["settings.createAccount"].waitForExistence(timeout: 8)
                && !app.descendants(matching: .any)["settings.signOut"].exists
        }
        let startPractice = app.descendants(matching: .any)["onboarding.startPractice"]
        if startPractice.waitForExistence(timeout: 3), startPractice.isHittable {
            startPractice.tap()
        }
        guard app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8) else { return false }
        let more = primaryTab("More", in: app)
        guard more.waitForExistence(timeout: 5), more.isHittable else { return false }
        more.tap()
        let settings = app.descendants(matching: .any)["more.settings"]
        guard settings.waitForExistence(timeout: 5), settings.isHittable else { return false }
        settings.tap()
        return app.descendants(matching: .any)["settings.createAccount"].waitForExistence(timeout: 8)
            && !app.descendants(matching: .any)["settings.signOut"].exists
    }

    @MainActor
    private func assertSignedOutState(in app: XCUIApplication) {
        let gateway = app.descendants(matching: .any)["screen.gateway"]
        if gateway.waitForExistence(timeout: 8) {
            let createAccount = app.descendants(matching: .any)["gateway.createAccount"]
            let signIn = app.descendants(matching: .any)["gateway.signIn"]
            XCTAssertTrue(createAccount.exists || signIn.exists)
            return
        }

        dismissOnboardingIfPresented(in: app)
        openTab("More", in: app)
        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.createAccount"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["settings.signOut"].exists)
    }

    @MainActor
    private func dismissOnboardingIfPresented(in app: XCUIApplication) {
        let startPractice = app.descendants(matching: .any)["onboarding.startPractice"]
        guard startPractice.waitForExistence(timeout: 3) else { return }
        startPractice.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func physicalDevApplication() -> XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.aryasalem.BrassTune.dev")
    }

    private func assertPhysicalDevProbeEnvironment(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
#if targetEnvironment(simulator)
        XCTFail("Physical provider probes must not run on a simulator.", file: file, line: line)
#endif
    }

    @MainActor
    private func waitForGoogleConsentSurface(in app: XCUIApplication) -> Bool {
        if isGoogleWebAuthenticationConsentAlert(app.alerts.firstMatch, timeout: 5) {
            return true
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        return isGoogleWebAuthenticationConsentAlert(springboard.alerts.firstMatch, timeout: 5)
    }

    @MainActor
    private func isGoogleWebAuthenticationConsentAlert(
        _ alert: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        guard alert.waitForExistence(timeout: timeout),
              alert.buttons["Continue"].exists,
              alert.buttons["Cancel"].exists else { return false }
        let containsSignIn = alert.label.localizedCaseInsensitiveContains("sign in")
            || alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "sign in")
        ).firstMatch.exists
        let containsAppName = alert.label.localizedCaseInsensitiveContains("BrassTune")
            || alert.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "BrassTune")
            ).firstMatch.exists
        return containsSignIn && containsAppName
    }

    @MainActor
    private func waitForAppleAuthorizationSurface() -> Bool {
        waitForAppleAuthorizationAction() != nil
    }

    @MainActor
    private func waitForAppleAuthorizationAction() -> XCUIElement? {
        let authKit = XCUIApplication(bundleIdentifier: "com.apple.AuthKitUIService")
        let deadline = Date().addingTimeInterval(20)
        repeat {
            if let action = appleAuthorizationAction(in: authKit) {
                return action
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return nil
    }

    @MainActor
    private func appleAuthorizationAction(in authKit: XCUIApplication) -> XCUIElement? {
        let stableAction = authKit.buttons.matching(
            NSPredicate(format: "identifier == %@", "SIWA_CONTINUE_BUTTON")
        ).firstMatch
        if stableAction.exists {
            // iOS 26 can expose the stable Sign in with Apple control before
            // its localized label settles (and the label is not guaranteed to
            // be one of the English fallbacks below). The system-owned stable
            // identifier is sufficient evidence that the native authorization
            // surface is present; attended runs never classify or enter the
            // credential content.
            return stableAction
        }
        let controls = [
            authKit.buttons["Continue"],
            authKit.buttons["Continue with Apple"],
            authKit.buttons["Sign In with Passcode"],
            authKit.buttons["Sign in with Passcode"],
            authKit.buttons["Use Passcode"]
        ]
        for control in controls where control.exists {
            return control
        }
        return nil
    }

    @MainActor
    private func launchPhysicalReleaseApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"] + extraArguments
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["gateway.continueAsGuest"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["onboarding.startPractice"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func allowMicrophonePermissionIfPresented() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        for label in ["Allow", "Allow While Using App", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
        XCTFail("A microphone permission alert appeared without an Allow action.")
    }

    @MainActor
    private func denyMicrophonePermission() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "A fresh `.dev` install must present the real microphone permission alert.")
        for label in ["Don’t Allow", "Don't Allow", "Deny"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
        XCTFail("The microphone permission alert appeared without a deny action.")
    }
#endif

    @MainActor
    private func launchFixtureApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"] + extraArguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func assertPrimaryTabs(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for title in ["Practice", "Tuner", "Scales", "Progress", "More"] {
            XCTAssertTrue(primaryTab(title, in: app).waitForExistence(timeout: 8), "Missing primary tab: \(title)", file: file, line: line)
        }
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tab = primaryTab(title, in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab: \(title)", file: file, line: line)
        tab.tap()
    }

    @MainActor
    private func primaryTab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let tabBarButton = app.tabBars.buttons[title]
        if tabBarButton.exists {
            return tabBarButton
        }

        // On iPad, the floating primary-navigation strip is exposed as regular
        // descendant buttons rather than an XCUIElementTypeTabBar on some iOS 26
        // configurations. Keep the primary tab-bar query when it is available,
        // then use the uniquely labelled button as the platform fallback.
        return app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
    }

    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Expected reachable control", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Control should be reachable", file: file, line: line)
    }

    @MainActor
    private func bringIntoViewFromTop(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Tab destinations preserve their ScrollView position. After an
        // orientation change the target may now sit above the viewport. In
        // landscape, app-level swipes can also follow device rather than view
        // coordinates, so drive the actual scroll container directly.
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2), "Expected a scrollable destination", file: file, line: line)
        for _ in 0..<8 {
            scrollView.swipeDown()
        }
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 2), "Expected reachable control", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Control should be reachable", file: file, line: line)
    }
}
