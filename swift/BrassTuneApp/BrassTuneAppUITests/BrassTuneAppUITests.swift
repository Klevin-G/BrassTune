import UIKit
import XCTest

final class BrassTuneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testArabicLaunchRendersCatalogCopyInsteadOfEnglishRuntimeStrings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE", "UITEST_RTL"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["الموالف"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["اعثر على المركز"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["tuner.readout"].label, "اعزف نغمة, جاهز")
        XCTAssertFalse(app.staticTexts["Find the center"].exists)
        XCTAssertFalse(app.staticTexts["Play a note"].exists)

        openTab("العزف المصاحب", in: app)
        let moreWays = app.descendants(matching: .any)["playAlong.moreWaysDisclosure"]
        XCTAssertTrue(moreWays.waitForExistence(timeout: 5))
        XCTAssertTrue(moreWays.label.contains("طرق أخرى للتدريب"))
        XCTAssertFalse(moreWays.label.contains("More ways to practice"))
        moreWays.tap()

        openTab("الإعدادات", in: app)
        let clearData = app.descendants(matching: .any)["settings.deleteAccount"]
        XCTAssertTrue(clearData.waitForExistence(timeout: 5))
        XCTAssertTrue(clearData.label.contains("مسح جميع بيانات التطبيق"))
        XCTAssertFalse(clearData.label.contains("Clear all app data"))
    }

    @MainActor
    func testArabicFirstRunLocalizesInstrumentSetupControlsAtRuntime() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_STATE",
            "UITEST_ENTRY_FLOW",
            "UITEST_AUTH_EMPTY",
            "UITEST_RTL",
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        app.buttons["gateway.continueAsGuest"].tap()

        let hero = app.descendants(matching: .any)["onboarding.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 8))
        XCTAssertTrue(hero.label.contains("اختر آلتك"))
        XCTAssertFalse(hero.label.contains("Choose your instrument"))

        let picker = app.descendants(matching: .any)["onboarding.instrumentPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("البوق في ب"))
        XCTAssertFalse(picker.label.contains("Trumpet in Bb"))

        let continueButton = app.buttons["onboarding.startPractice"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.label.contains("المتابعة إلى الموالف"))
        XCTAssertFalse(continueButton.label.contains("Continue to Tuner"))
    }

    @MainActor
    func testFirstRunGatewayAndInstrumentSetupLeadToTunerAndPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        assertAppFillsScreen(app)
        for identifier in [
            "gateway.continueAsGuest",
            "gateway.signIn",
            "gateway.createAccount",
            "gateway.classCode",
        ] {
            assertVisibleAndHittable(app.descendants(matching: .any)[identifier], in: app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["gateway.createAccount"].label.contains("Create free account"))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.accountConfigurationUnavailable"].exists)
        keepScreenshot(named: "First run - account gateway", from: app)
        app.buttons["gateway.continueAsGuest"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.hero"].waitForExistence(timeout: 8),
            "The one-screen instrument setup should follow guest entry"
        )
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.hero"].label.contains("Choose your instrument"))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.hero"].label.contains("concert-pitch transposition"))
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.hero"].label.contains("change it later"))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.hero"].label.contains("Step"))
        XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Instrument setup should replace the main app instead of covering a running Tuner")
        XCTAssertFalse(app.descendants(matching: .any)["screen.tuner"].exists)
        assertAppFillsScreen(app)
        assertVisibleAndHittable(app.descendants(matching: .any)["onboarding.instrumentPicker"], in: app)
        assertVisibleAndHittable(app.buttons["onboarding.startPractice"], in: app)
        XCTAssertFalse(app.buttons["onboarding.notNow"].exists)
        keepScreenshot(named: "First run - instrument setup", from: app)
        app.buttons["onboarding.startPractice"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 5),
            "Finishing setup should lead directly to Tuner"
        )

        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.tuner"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.hero"].exists, "Completion must persist across relaunch")
    }

    @MainActor
    func testUnconfiguredGatewayExposesBothRecoverableAccountActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        for identifier in ["gateway.signIn", "gateway.createAccount"] {
            let action = app.descendants(matching: .any)[identifier]
            assertVisibleAndHittable(action, in: app)
            action.tap()

            let apple = app.descendants(matching: .any)["gateway.authAppleSignIn"]
            let google = app.descendants(matching: .any)["gateway.authGoogleSignIn"]
            XCTAssertTrue(apple.waitForExistence(timeout: 5))
            XCTAssertFalse(apple.isEnabled)
            XCTAssertTrue(google.exists)
            XCTAssertFalse(google.isEnabled)
            XCTAssertTrue(app.descendants(matching: .any)["gateway.authProvidersRecovery"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["gateway.authUnavailable"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["gateway.authGuestEscape"].exists)
            XCTAssertTrue(app.buttons["Not now"].exists)
            app.buttons["Not now"].tap()

            XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testAuthUnavailableClassIntentShowsRecoveryInsteadOfDeadForm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launch()

        let classCode = app.descendants(matching: .any)["gateway.classCode"]
        XCTAssertTrue(classCode.waitForExistence(timeout: 8))
        classCode.tap()

        XCTAssertTrue(app.descendants(matching: .any)["gateway.classIntent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authUnavailable"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authAppleSignIn"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.authAppleSignIn"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authGoogleSignIn"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.authGoogleSignIn"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authProvidersRecovery"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.email"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.password"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.submitAuth"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["gateway.passwordReset"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authGuestEscape"].exists)
        XCTAssertTrue(app.buttons["Not now"].exists)
    }

    @MainActor
    func testSignedOutClassesRoutesToCompleteRecoverableAuthSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["gateway.continueAsGuest"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["gateway.continueAsGuest"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.startPractice"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["onboarding.startPractice"].tap()
        XCTAssertTrue(primaryNavigationControl("Tuner", in: app).waitForExistence(timeout: 8))

        openTab("Class", in: app)
        let signIn = app.descendants(matching: .any)["classes.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["classes.appleSignIn"].exists)
        signIn.tap()

        let apple = app.descendants(matching: .any)["gateway.authAppleSignIn"]
        let google = app.descendants(matching: .any)["gateway.authGoogleSignIn"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertFalse(apple.isEnabled)
        XCTAssertTrue(google.exists)
        XCTAssertFalse(google.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authProvidersRecovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authGuestEscape"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.recommendation"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.startWarmup"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "playAlong.startWarmup").count, 1)
        let moreWays = app.descendants(matching: .any)["playAlong.moreWaysDisclosure"]
        XCTAssertTrue(moreWays.waitForExistence(timeout: 5))
        moreWays.tap()
        let exercisePicker = app.descendants(matching: .any)["playAlong.exercisePicker"]
        for _ in 0..<4 where !exercisePicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(exercisePicker.waitForExistence(timeout: 5))
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
        XCTAssertEqual(app.descendants(matching: .any)["tuner.readout"].label, "Play a note, Ready")
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
        XCTAssertTrue(
            floatingStop.waitForNonExistence(timeout: 5),
            "The recording transport should finish dismissing before the next navigation action."
        )

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.today"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["progress.gettingStarted"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any)["progress.milestone.first-note"].value as? String,
            "Done"
        )
        XCTAssertTrue(app.descendants(matching: .any)["progress.thisWeek"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["progress.nextStep"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["progress.allSessions"].exists)

        openTab("Settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
        let unavailableAccount = app.descendants(matching: .any)["settings.accountConfigurationUnavailable"]
        XCTAssertTrue(unavailableAccount.waitForExistence(timeout: 5))
        XCTAssertTrue(unavailableAccount.label.localizedCaseInsensitiveContains("Account sign-in needs secure"))

        let advancedTuner = app.descendants(matching: .any)["settings.advancedTunerSettings"]
        XCTAssertTrue(advancedTuner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["settings.referencePitchStepper"].exists)
        advancedTuner.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.referencePitchStepper"].waitForExistence(timeout: 8),
            "A4 should live behind Advanced tuner settings"
        )

        XCTAssertTrue(app.descendants(matching: .any)["settings.metronomeLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.scoresLink"].waitForExistence(timeout: 5))

        let reviewSetup = app.descendants(matching: .any)["settings.reopenOnboarding"]
        tapWhenSafelyVisible(reviewSetup, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let cancelSetup = app.buttons["onboarding.cancel"]
        XCTAssertTrue(cancelSetup.waitForExistence(timeout: 5))
        cancelSetup.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            primaryNavigationControl("Settings", in: app).isSelected,
            "Canceling a setup review should return to Settings"
        )
    }

    @MainActor
    func testClassLegalAndClearAllDataSurfaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        XCTAssertTrue(primaryNavigationControl("Tuner", in: app).waitForExistence(timeout: 8))
        openTab("Class", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.classes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["classes.joinPrivacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["classes.activePicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo brass studio"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["classes.leave.1"].exists)
        app.descendants(matching: .any)["classes.activePicker"].tap()
        XCTAssertTrue(
            app.buttons["Second demo class"].waitForExistence(timeout: 5),
            "Every membership should be available from the active-Class picker."
        )
        app.buttons["Second demo class"].tap()
        XCTAssertTrue(app.staticTexts["Second demo class"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["classes.director.averageDistance.101"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["classes.director.inTune.101"].exists)
        let overallAverage = app.descendants(matching: .any)["classes.director.averageDistance.overall"]
        let classScrollView = app.scrollViews.firstMatch
        for _ in 0..<12 where !overallAverage.exists {
            classScrollView.swipeUp()
        }
        XCTAssertTrue(overallAverage.waitForExistence(timeout: 5))
        openTab("Settings", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.privacyLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.termsLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.supportLink"].waitForExistence(timeout: 5))

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
    func testClearLocalPracticeDataCancelAndConfirmFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        XCTAssertTrue(primaryNavigationControl("Tuner", in: app).waitForExistence(timeout: 8))
        let tunerStart = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(tunerStart.waitForExistence(timeout: 5))
        tunerStart.tap()
        let floatingStop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(floatingStop.waitForExistence(timeout: 8))
        floatingStop.tap()
        openTab("Settings", in: app)

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
            app.descendants(matching: .any)["progress.today"].waitForExistence(timeout: 5),
            "Confirming the alert should clear local practice history"
        )
        XCTAssertTrue(app.staticTexts["No practice saved today"].exists)
    }

    @MainActor
    func testProgressOnlyOffersResumeWarmupAfterCheckpointExists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        openTab("Progress", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.progress"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["progress.resumeWarmup"].exists)

        openTab("Play-Along", in: app)
        let warmup = app.descendants(matching: .any)["playAlong.startWarmup"]
        XCTAssertTrue(warmup.waitForExistence(timeout: 5))
        warmup.tap()
        let start = app.descendants(matching: .any)["warmup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        openTab("Progress", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["progress.resumeWarmup"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testFirstStartListeningShowsOneTimeMicrophoneRationale() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_FIXTURES",
            "UITEST_RESET_STATE",
            "UITEST_MIC_RATIONALE",
        ]
        app.launch()

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["microphone.rationale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["microphone.rationaleContinue"].isHittable)
        let disclosure = app.staticTexts["microphone.rationaleDisclosure"]
        XCTAssertTrue(disclosure.exists)
        XCTAssertTrue(disclosure.label.contains("save practice results"))
        XCTAssertTrue(disclosure.label.contains("Raw microphone audio is not saved"))
        XCTAssertFalse(disclosure.label.contains("save recordings"))
        let notNow = app.descendants(matching: .any)["microphone.rationaleNotNow"]
        XCTAssertTrue(notNow.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["tuner.floating.stop"].exists)
        notNow.tap()

        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["microphone.rationale"].waitForExistence(timeout: 1),
            "The rationale must not repeat after either explicit choice."
        )
        XCTAssertTrue(app.descendants(matching: .any)["tuner.floating.stop"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testStartingDroneToneStopsAndSavesActiveTunerRecordingExactlyOnce() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        let tunerStart = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(tunerStart.waitForExistence(timeout: 8))
        tunerStart.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["tuner.floating.stop"].waitForExistence(timeout: 8),
            "The tuner should be recording before audio ownership moves to the drone."
        )

        let droneLink = app.descendants(matching: .any)["tuner.droneIntervalLink"]
        tapWhenSafelyVisible(droneLink, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 5))

        let droneToggle = app.descendants(matching: .any)["drone.toggle"]
        XCTAssertTrue(droneToggle.waitForExistence(timeout: 5))
        droneToggle.tap()
        XCTAssertTrue(
            app.buttons["Stop reference tone"].waitForExistence(timeout: 5),
            "The reference tone should acquire audio ownership after the tuner take is finalized."
        )

        openTab("Progress", in: app)
        let allSessions = app.descendants(matching: .any)["progress.allSessions"]
        XCTAssertTrue(
            allSessions.waitForExistence(timeout: 5),
            "Starting the drone should save the active tuner take instead of discarding it."
        )
        tapWhenSafelyVisible(allSessions, in: app)

        let savedRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "sessions.row.")
        )
        XCTAssertEqual(savedRows.count, 1, "The tuner take must be finalized exactly once.")
    }

    @MainActor
    func testLocalPracticeToolboxIsReachableFromFiveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        openTab("Play-Along", in: app)
        let moreWays = app.descendants(matching: .any)["playAlong.moreWaysDisclosure"]
        XCTAssertTrue(moreWays.waitForExistence(timeout: 8))
        moreWays.tap()
        XCTAssertTrue(app.descendants(matching: .any)["playAlong.startWarmup"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Create a Play-Along exercise"].exists)
        XCTAssertTrue(app.buttons["Offline practice packs"].exists)
        XCTAssertTrue(app.buttons["Add to favorites"].exists)

        let builder = app.buttons["Create a Play-Along exercise"]
        tapWhenSafelyVisible(builder, in: app)
        XCTAssertTrue(app.navigationBars["Exercise builder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["exerciseBuilder.save"].exists)
        app.navigationBars.buttons["Play-Along"].tap()

        let warmup = app.descendants(matching: .any)["playAlong.startWarmup"]
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
        let goalSteppers = app.steppers.matching(identifier: "progress.weeklyGoal")
        XCTAssertEqual(goalSteppers.count, 2)
        XCTAssertTrue((0..<goalSteppers.count).map { goalSteppers.element(boundBy: $0).label }.contains { $0.contains("15 minutes") })
        XCTAssertTrue((0..<goalSteppers.count).map { goalSteppers.element(boundBy: $0).label }.contains { $0.contains("3 sessions") })
        XCTAssertFalse(app.descendants(matching: .any)["progress.weakTransition"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["progress.weakTransitionInsufficient"].exists)

        openTab("Settings", in: app)
        let metronomeLink = app.descendants(matching: .any)["settings.metronomeLink"]
        tapWhenSafelyVisible(metronomeLink, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["metronome.savePreset"].exists)

        let advancedRhythm = app.buttons["metronome.advancedRhythm"]
        tapWhenSafelyVisible(advancedRhythm, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["metronome.beatUnitPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["metronome.accentFirstBeat"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["metronome.countIn"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["metronome.stepper"].exists)
    }

    @MainActor
    func testNamedPracticeControlsExposeContextAndMinimumTargets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        openTab("Play-Along", in: app)
        let moreWays = app.descendants(matching: .any)["playAlong.moreWaysDisclosure"]
        XCTAssertTrue(moreWays.waitForExistence(timeout: 8))
        moreWays.tap()

        let builder = app.descendants(matching: .any)["practice.quickStart.builder"]
        for _ in 0..<4 where !builder.exists {
            app.swipeUp()
        }
        tapWhenSafelyVisible(builder, in: app)
        let exerciseName = app.descendants(matching: .any)["exerciseBuilder.title"]
        XCTAssertTrue(exerciseName.waitForExistence(timeout: 5))
        exerciseName.tap()
        exerciseName.typeText("Marching exercise")
        app.keyboards.buttons["Return"].tap()
        tapWhenSafelyVisible(app.descendants(matching: .any)["exerciseBuilder.save"], in: app)

        tapWhenSafelyVisible(app.descendants(matching: .any)["practice.quickStart.builder"], in: app)
        let exerciseControls = [
            ("exerciseManager.edit.Marching exercise", "Edit Marching exercise"),
            ("exerciseManager.delete.Marching exercise", "Delete Marching exercise"),
        ]
        for (identifier, label) in exerciseControls {
            let control = app.descendants(matching: .any)[identifier]
            bringSafelyIntoView(control, in: app)
            XCTAssertEqual(control.label, label)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        openTab("Settings", in: app)
        tapWhenSafelyVisible(app.descendants(matching: .any)["settings.metronomeLink"], in: app)
        let presetName = app.descendants(matching: .any)["metronome.presetName"]
        XCTAssertTrue(presetName.waitForExistence(timeout: 5))
        presetName.tap()
        presetName.typeText("Marching tempo")
        app.keyboards.buttons["Return"].tap()
        app.descendants(matching: .any)["metronome.savePreset"].tap()

        let presetControls = [
            ("metronome.preset.apply.Marching tempo", "Apply Marching tempo"),
            ("metronome.preset.rename.Marching tempo", "Rename Marching tempo"),
            ("metronome.preset.delete.Marching tempo", "Delete Marching tempo"),
        ]
        for (identifier, label) in presetControls {
            let control = app.descendants(matching: .any)[identifier]
            bringSafelyIntoView(control, in: app)
            XCTAssertEqual(control.label, label)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
    }

    @MainActor
    func testSmallPhoneMaximumDynamicTypeKeepsPrimaryTunerAndRecoveryActionsAboveTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_FIXTURES",
            "UITEST_RESET_STATE",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        let start = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        XCTAssertLessThan(start.frame.maxY, app.tabBars.firstMatch.frame.minY)

        openTab("Settings", in: app)
        let advanced = app.descendants(matching: .any)["settings.advancedTunerSettings"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(advanced.frame.height, 44)
        openTab("Class", in: app)
        let leave = app.descendants(matching: .any)["classes.leave.1"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(leave.frame.height, 44)

        app.terminate()
        app.launchArguments = [
            "UITEST_FIXTURES",
            "UITEST_RESET_STATE",
            "UITEST_MIC_DENIED",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        let recovery = app.descendants(matching: .any)["microphone.openSettings"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 8))
        XCTAssertTrue(recovery.isHittable)
        XCTAssertGreaterThanOrEqual(recovery.frame.height, 44)
        XCTAssertLessThan(recovery.frame.maxY, app.tabBars.firstMatch.frame.minY)
        XCTAssertTrue(app.descendants(matching: .any)["microphone.retry"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["microphone.practiceWithoutListening"].exists)
    }

    @MainActor
    func testMaximumDynamicTypeKeepsGatewayAndInstrumentSetupReadableAndActionable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_STATE",
            "UITEST_ENTRY_FLOW",
            "UITEST_AUTH_EMPTY",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["BRASSTUNE_SUPABASE_URL"] = "https://ui-tests.invalid"
        app.launchEnvironment["BRASSTUNE_SUPABASE_PUBLISHABLE_KEY"] = "sb_publishable_ui_tests"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["screen.gateway"].waitForExistence(timeout: 8))
        assertAppFillsScreen(app)
        for identifier in [
            "gateway.continueAsGuest",
            "gateway.signIn",
            "gateway.createAccount",
            "gateway.classCode",
        ] {
            let control = app.descendants(matching: .any)[identifier]
            assertVisibleAndHittable(control, in: app)
        }
        keepScreenshot(named: "Maximum Dynamic Type - account gateway", from: app)

        app.descendants(matching: .any)["gateway.signIn"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authAppleSignIn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authGoogleSignIn"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.passwordReset"].exists)
        XCTAssertTrue(app.buttons["Not now"].exists)
        app.buttons["Not now"].tap()

        let guestEntry = app.descendants(matching: .any)["gateway.continueAsGuest"]
        guestEntry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.instrumentSetup"].waitForExistence(timeout: 8))
        assertAppFillsScreen(app)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let instrument = app.descendants(matching: .any)["onboarding.instrumentPicker"]
        let start = app.descendants(matching: .any)["onboarding.startPractice"]
        XCTAssertTrue(instrument.waitForExistence(timeout: 8))
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        assertVisibleAndHittable(instrument, in: app)
        assertVisibleAndHittable(start, in: app)
        XCTAssertLessThan(
            instrument.frame.maxY,
            start.frame.minY,
            "The menu-style instrument picker must not compress into the sticky setup action"
        )
        keepScreenshot(named: "Maximum Dynamic Type - instrument setup", from: app)
    }

    @MainActor
    func testConfiguredAuthShowsGoogleEmailAndUnavailableAppleWithGuestEscape() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_STATE",
            "UITEST_ENTRY_FLOW",
            "UITEST_AUTH_EMPTY",
            "UITEST_AUTH_PROVIDERS",
        ]
        app.launchEnvironment["BRASSTUNE_SUPABASE_URL"] = "https://ui-tests.invalid"
        app.launchEnvironment["BRASSTUNE_SUPABASE_PUBLISHABLE_KEY"] = "sb_publishable_ui_tests"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["gateway.signIn"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["gateway.signIn"].tap()

        let apple = app.descendants(matching: .any)["gateway.authAppleSignIn"]
        let google = app.descendants(matching: .any)["gateway.authGoogleSignIn"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        XCTAssertFalse(apple.isEnabled)
        XCTAssertTrue(google.exists)
        XCTAssertTrue(google.isEnabled)
        XCTAssertEqual(google.label, "Sign in with Google")
        XCTAssertGreaterThanOrEqual(google.frame.height, 50)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.email"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.password"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gateway.authProvidersRecovery"].exists)
        XCTAssertTrue(app.buttons["Not now"].exists)
        keepScreenshot(named: "Native auth providers - Google available Apple recovery", from: app)
    }

    @MainActor
    func testFloatingTabBarKeepsPlayAlongProgressAndSettingsActionsUnobscured() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8))

        openTab("Play-Along", in: app)
        assertAboveTabBar(
            app.descendants(matching: .any)["playAlong.startWarmup"],
            tabBar: tabBar,
            in: app
        )

        openTab("Progress", in: app)
        let goalSteppers = app.steppers.matching(identifier: "progress.weeklyGoal")
        XCTAssertEqual(goalSteppers.count, 2)
        for index in 0..<goalSteppers.count {
            let goalStepper = goalSteppers.element(boundBy: index)
            bringSafelyIntoView(goalStepper, in: app)
            XCTAssertTrue(goalStepper.isHittable, "Weekly-goal controls must not sit behind a sticky CTA.")
            XCTAssertLessThan(goalStepper.frame.maxY, tabBar.frame.minY)
        }
        let openTuner = app.descendants(matching: .any)["progress.openTuner"]
        bringSafelyIntoView(openTuner, in: app)
        XCTAssertTrue(openTuner.isHittable)
        XCTAssertLessThan(openTuner.frame.maxY, tabBar.frame.minY)

        openTab("Settings", in: app)
        let clearAllData = app.descendants(matching: .any)["settings.deleteAccount"]
        bringSafelyIntoView(clearAllData, in: app)
        XCTAssertTrue(clearAllData.isHittable)
        XCTAssertLessThan(clearAllData.frame.maxY, tabBar.frame.minY)
    }

    @MainActor
    func testPersistenceFailureBannerHasLaunchCoverage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE", "UITEST_PERSISTENCE_ERROR"]
        app.launch()
        let banner = app.descendants(matching: .any)["app.persistenceError"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        XCTAssertTrue(banner.label.contains("couldn't save"))
    }

    @MainActor
    func testFirstPersistedGuestResultShowsOneTimeNonblockingSafetyPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()

        XCTAssertFalse(app.descendants(matching: .any)["guest.progressSafetyPrompt"].exists)
        let start = app.descendants(matching: .any)["tuner.recordButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let stop = app.descendants(matching: .any)["tuner.floating.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()

        let prompt = app.descendants(matching: .any)["guest.progressSafetyPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["guest.progressSafetyCreate"].exists)
        let dismiss = app.descendants(matching: .any)["guest.progressSafetyDismiss"]
        XCTAssertTrue(dismiss.exists)
        XCTAssertTrue(
            primaryNavigationControl("Tuner", in: app).isHittable,
            "The prompt must not block practice navigation."
        )
        dismiss.tap()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))

        start.tap()
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1), "The safety prompt must only appear once.")

        openTab("Settings", in: app)
        let haptics = app.switches["settings.successHaptics"]
        XCTAssertTrue(haptics.waitForExistence(timeout: 5))
        XCTAssertTrue(haptics.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Reduce Motion")
        ).firstMatch.exists)
    }

    @MainActor
    private func assertFiveTabInformationArchitecture(in app: XCUIApplication) {
        for title in ["Play-Along", "Tuner", "Progress", "Class", "Settings"] {
            XCTAssertTrue(
                primaryNavigationControl(title, in: app).waitForExistence(timeout: 8),
                "\(title) should exist in the adaptive primary navigation"
            )
        }

        for removedTab in ["Home", "Practice", "Analytics", "Coach", "More"] {
            let removedControl = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", removedTab))
                .firstMatch
            XCTAssertFalse(
                removedControl.exists,
                "\(removedTab) should not remain in the focused primary navigation"
            )
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
        bringSafelyIntoView(element, in: app, file: file, line: line)
        element.tap()
    }

    @MainActor
    private func bringSafelyIntoView(
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
    private func assertAboveTabBar(
        _ element: XCUIElement,
        tabBar: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Expected sticky action", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Sticky action should be immediately hittable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        XCTAssertLessThan(element.frame.maxY, tabBar.frame.minY, file: file, line: line)
    }

    @MainActor
    private func assertAppFillsScreen(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "The app should own a window", file: file, line: line)
        let screenSize = XCUIScreen.main.screenshot().image.size
        XCTAssertEqual(window.frame.minX, 0, accuracy: 1, file: file, line: line)
        XCTAssertEqual(window.frame.minY, 0, accuracy: 1, file: file, line: line)
        XCTAssertEqual(window.frame.width, screenSize.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(window.frame.height, screenSize.height, accuracy: 1, file: file, line: line)
    }

    @MainActor
    private func assertVisibleAndHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected visible control", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Expected immediately hittable control", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(element.frame.minY, windowFrame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, windowFrame.maxY, file: file, line: line)
    }

    @MainActor
    private func keepScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openTab(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let navigationControl = primaryNavigationControl(title, in: app)
        XCTAssertTrue(
            navigationControl.waitForExistence(timeout: 5),
            "\(title) should exist in the adaptive primary navigation",
            file: file,
            line: line
        )
        navigationControl.tap()
    }

    @MainActor
    private func primaryNavigationControl(
        _ title: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let compactTab = app.tabBars.buttons[title]
        if compactTab.exists {
            return compactTab
        }

        let adaptiveMatches = app.buttons
            .matching(NSPredicate(format: "label == %@", title))
        _ = adaptiveMatches.firstMatch.waitForExistence(timeout: 2)

        if adaptiveMatches.count > 0 {
            return adaptiveMatches.element(boundBy: adaptiveMatches.count - 1)
        }
        return compactTab.exists ? compactTab : adaptiveMatches.firstMatch
    }
}
