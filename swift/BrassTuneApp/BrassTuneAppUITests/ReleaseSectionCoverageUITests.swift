import XCTest

final class ReleaseSectionCoverageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuidedPracticeCustomExerciseCanCreateEditAndDelete() throws {
        let app = launchFixtureApp()
        openGuidedPractice(in: app)

        let disclosure = element("playAlong.moreWaysDisclosure", in: app)
        if !disclosure.valueDescription.contains("Expanded") {
            disclosure.tap()
        }
        let builder = element("practice.quickStart.builder", in: app)
        bringIntoView(builder, in: app)
        XCTAssertTrue(builder.exists)
        builder.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.exerciseBuilder"].waitForExistence(timeout: 5))

        let initialName = "Release UI Exercise"
        replaceText(in: app.textFields["exerciseBuilder.title"], with: initialName)
        app.buttons["exerciseBuilder.addNote"].tap()
        app.buttons["exerciseBuilder.addNote"].tap()
        app.buttons["exerciseBuilder.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.playAlong"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["practice.quickStart.builder"].tap()
        let edit = element("exerciseManager.edit.\(initialName)", in: app)
        bringIntoView(edit, in: app)
        XCTAssertTrue(edit.isHittable)
        edit.tap()

        let updatedName = "Release UI Exercise Updated"
        replaceText(in: app.textFields["exerciseBuilder.title"], with: updatedName)
        app.buttons["exerciseBuilder.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.exerciseBuilder"].waitForExistence(timeout: 5))

        let delete = element("exerciseManager.delete.\(updatedName)", in: app)
        bringIntoView(delete, in: app)
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.exerciseBuilder"].exists)
        XCTAssertFalse(element("exerciseManager.edit.\(updatedName)", in: app).exists)
        XCTAssertFalse(element("exerciseManager.delete.\(updatedName)", in: app).exists)
    }

    @MainActor
    func testNamedMetronomePresetCanSaveRejectDuplicateApplyRenameAndDelete() throws {
        let app = launchFixtureApp()
        let metronome = app.buttons["practice.metronome"]
        XCTAssertTrue(metronome.waitForExistence(timeout: 8))
        metronome.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5))
        app.buttons["metronome.settings"].tap()

        let tempo = app.steppers["metronome.stepper"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        tempo.buttons["metronome.stepper-Increment"].tap()
        let savedTempoLabel = tempo.label
        let name = "Release UI Pulse"
        let presetName = app.textFields["metronome.presetName"]
        bringIntoView(presetName, in: app)
        replaceText(in: presetName, with: name)
        app.buttons["metronome.savePreset"].tap()
        dismissKeyboard(in: app)
        let apply = element("metronome.preset.apply.\(name)", in: app)
        bringIntoView(apply, in: app, scrollView: app.scrollViews.firstMatch)
        XCTAssertTrue(apply.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier == %@", "metronome.preset.apply.\(name)")).count, 1)

        replaceText(in: presetName, with: name)
        app.buttons["metronome.savePreset"].tap()
        dismissKeyboard(in: app)
        let status = app.descendants(matching: .any)["metronome.presetStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("unique"))

        tempo.buttons["metronome.stepper-Increment"].tap()
        bringIntoView(apply, in: app, scrollView: app.scrollViews.firstMatch)
        XCTAssertTrue(apply.isHittable)
        apply.tap()
        XCTAssertEqual(tempo.label, savedTempoLabel)

        let rename = element("metronome.preset.rename.\(name)", in: app)
        bringIntoView(rename, in: app, scrollView: app.scrollViews.firstMatch)
        XCTAssertTrue(rename.exists)
        rename.tap()
        let renameField = app.collectionViews.firstMatch.textFields["Preset name"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        let renamed = "Release UI Pulse Renamed"
        replaceText(in: renameField, with: renamed)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(element("metronome.preset.apply.\(renamed)", in: app).waitForExistence(timeout: 5))

        let delete = element("metronome.preset.delete.\(renamed)", in: app)
        bringIntoView(delete, in: app, scrollView: app.scrollViews.firstMatch)
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertTrue(app.textFields["metronome.presetName"].exists)
        XCTAssertFalse(element("metronome.preset.apply.\(renamed)", in: app).exists)
        XCTAssertFalse(element("metronome.preset.delete.\(renamed)", in: app).exists)
    }

    @MainActor
    func testMetronomeTempoWheelAndOneBPMControlsRemainReachable() throws {
        let app = launchFixtureApp()
        let metronome = app.buttons["practice.metronome"]
        XCTAssertTrue(metronome.waitForExistence(timeout: 8))
        metronome.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.metronome"].waitForExistence(timeout: 5))

        let bpm = element("metronome.bpm", in: app)
        XCTAssertTrue(bpm.waitForExistence(timeout: 5))
        let initialBPM = bpm.label
        let up = app.buttons["metronome.tempoUp"]
        let down = app.buttons["metronome.tempoDown"]
        XCTAssertTrue(up.isHittable)
        XCTAssertTrue(down.isHittable)
        up.tap()
        XCTAssertNotEqual(bpm.label, initialBPM, "The compact control must change tempo by one BPM.")
        down.tap()
        XCTAssertEqual(bpm.label, initialBPM, "The paired compact controls must restore the prior one-BPM value.")

        app.buttons["metronome.settings"].tap()
        let wheel = element("metronome.tempoWheel", in: app)
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        XCTAssertTrue(wheel.isHittable)
        XCTAssertTrue(app.steppers["metronome.stepper"].exists)
    }

    @MainActor
    func testDroneTriadAndTemperamentMenusChangeTheAvailableControls() throws {
        let app = launchFixtureApp()
        let drone = app.descendants(matching: .any)["practice.drone"]
        XCTAssertTrue(drone.waitForExistence(timeout: 8))
        drone.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.droneInterval"].waitForExistence(timeout: 5))

        let voicing = element("drone.voicing", in: app)
        XCTAssertTrue(voicing.waitForExistence(timeout: 5))
        voicing.tap()
        let majorTriad = app.buttons["Major triad"]
        XCTAssertTrue(majorTriad.waitForExistence(timeout: 5))
        majorTriad.tap()
        XCTAssertFalse(element("drone.interval", in: app).exists, "Triad voicings must not expose the interval-only control.")

        voicing.tap()
        let minorTriad = app.buttons["Minor triad"]
        XCTAssertTrue(minorTriad.waitForExistence(timeout: 5))
        minorTriad.tap()
        XCTAssertFalse(element("drone.interval", in: app).exists)

        let temperament = element("drone.temperament", in: app)
        XCTAssertTrue(temperament.waitForExistence(timeout: 5))
        temperament.tap()
        let justIntonation = app.buttons["Just intonation"]
        XCTAssertTrue(justIntonation.waitForExistence(timeout: 5))
        justIntonation.tap()
        XCTAssertTrue((temperament.label + " " + temperament.valueDescription).localizedCaseInsensitiveContains("just"))

        temperament.tap()
        let equalTemperament = app.buttons["Equal temperament"]
        XCTAssertTrue(equalTemperament.waitForExistence(timeout: 5))
        equalTemperament.tap()
        XCTAssertTrue((temperament.label + " " + temperament.valueDescription).localizedCaseInsensitiveContains("equal"))
    }

    @MainActor
    func testScalePlayAlongDoneReturnsToScalesWithoutLeavingTransportRunning() throws {
        let app = launchFixtureApp()
        openTab("Scales", in: app)
        let start = element("scales.start", in: app)
        if !start.exists {
            print("SCALE_START_DIAGNOSTIC\n" + app.debugDescription)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Scale start layout"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isHittable)
        start.tap()

        XCTAssertTrue(element("playAlong.targetNote", in: app).waitForExistence(timeout: 5))
        let done = app.buttons["playAlong.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(element("screen.scales", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("playAlong.stop", in: app).exists)
    }

    @MainActor
    func testSettingsColorThemeChoiceSurvivesLeavingAndReturningToSettings() throws {
        let app = launchFixtureApp()
        openTab("More", in: app)
        let settings = element("more.settings", in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let theme = element("settings.colorTheme", in: app)
        bringIntoView(theme, in: app)
        XCTAssertTrue(theme.isHittable)
        let system = app.buttons["System"].firstMatch
        let light = app.buttons["Light"].firstMatch
        let dark = app.buttons["Dark"].firstMatch
        XCTAssertTrue(system.exists)
        XCTAssertTrue(light.exists)
        XCTAssertTrue(dark.exists)
        light.tap()
        XCTAssertTrue(light.isSelected)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element("more.settings", in: app).waitForExistence(timeout: 5))
        element("more.settings", in: app).tap()
        let restoredLight = app.buttons["Light"].firstMatch
        XCTAssertTrue(restoredLight.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredLight.isSelected, "The chosen color theme must persist while navigating the app.")
        dark.tap()
        XCTAssertTrue(dark.isSelected)
    }

    @MainActor
    func testSettingsLanguageHapticsAndAdvancedA4ControlsWork() throws {
        let app = launchFixtureApp()
        openTab("More", in: app)
        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 5))

        let advanced = element("settings.advancedTunerSettings", in: app)
        let settingsScroll = app.scrollViews["screen.settings"]
        dragUp(in: settingsScroll)
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        XCTAssertTrue(advanced.isHittable)
        advanced.tap()
        let referencePitch = element("settings.referencePitchStepper", in: app)
        bringIntoView(referencePitch, in: app)
        XCTAssertTrue(referencePitch.exists)
        let initialPitch = referencePitch.label
        referencePitch.buttons["settings.referencePitchStepper-Increment"].tap()
        XCTAssertNotEqual(referencePitch.label, initialPitch)

        let haptics = element("settings.successHaptics", in: app)
        bringIntoView(haptics, in: app, scrollView: settingsScroll)
        XCTAssertTrue(haptics.waitForExistence(timeout: 5))
        XCTAssertTrue(haptics.isHittable)
        let initialHaptics = haptics.value as? String
        haptics.tap()
        XCTAssertNotEqual(haptics.value as? String, initialHaptics)

        let language = element("settings.languagePicker", in: app)
        for _ in 0..<5 {
            if language.exists, language.isHittable { break }
            dragDown(in: settingsScroll)
        }
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertTrue(language.isHittable)
        language.tap()
        let arabic = app.buttons["العربية"]
        XCTAssertTrue(arabic.waitForExistence(timeout: 5))
        arabic.tap()
        let updatedLanguage = element("settings.languagePicker", in: app)
        XCTAssertTrue(updatedLanguage.label.contains("العربية") || updatedLanguage.value as? String == "العربية")
        XCTAssertTrue(app.tabBars.buttons["المقاييس"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.practice"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func openGuidedPractice(in app: XCUIApplication) {
        let playAlong = app.descendants(matching: .any)["practice.playAlong"]
        XCTAssertTrue(playAlong.waitForExistence(timeout: 8))
        playAlong.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.playAlong"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.waitForExistence(timeout: 3), tab.isHittable {
            tab.tap()
            return
        }
        let floating = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(floating.waitForExistence(timeout: 5), "Missing primary tab \(title)")
        floating.tap()
    }

    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
    }

    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication, scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3), "Expected a scrollable surface")
        for _ in 0..<5 {
            if element.exists, element.isHittable { return }
            scrollView.swipeUp()
        }
    }

    @MainActor
    private func dragUp(in scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3), "Expected a scrollable surface")
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func dragDown(in scrollView: XCUIElement) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3), "Expected a scrollable surface")
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        let existingCharacterCount = element.value as? String
        if let existingCharacterCount, !existingCharacterCount.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingCharacterCount.count))
        }
        element.typeText(value)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists, keyboard.buttons["Return"].exists {
            keyboard.buttons["Return"].tap()
        }
    }
}

private extension XCUIElement {
    var valueDescription: String {
        (value as? String) ?? ""
    }
}
