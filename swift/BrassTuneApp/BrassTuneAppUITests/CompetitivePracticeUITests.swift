import XCTest

final class CompetitivePracticeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPhysicalGapTrainerRealOutputCycle() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical metronome check requires the explicitly selected USB phone.")
#else
        guard ProcessInfo.processInfo.environment["BRASSTUNE_PHYSICAL_GAP"] == "1" else {
            throw XCTSkip("Opt in with BRASSTUNE_PHYSICAL_GAP=1.")
        }
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = XCUIApplication(bundleIdentifier: "com.aryasalem.BrassTune.dev")
        app.launchArguments = []
        app.launch()
        enterGuest(app)
        openMetronome(app)
        element("metronome.settings", app).tap()
        if app.pickerWheels.firstMatch.waitForExistence(timeout: 3) {
            app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "92 BPM")
        }
        let visualOnly = element("metronome.visualOnly", app)
        reveal(visualOnly, app)
        setSwitch(visualOnly, enabled: false)
        let volume = element("metronome.volume", app)
        reveal(volume, app)
        volume.adjust(toNormalizedSliderPosition: 0.4)
        let toggle = element("metronome.gapEnabled", app)
        reveal(toggle, app)
        setSwitch(toggle, enabled: true)
        for id in ["metronome.gapAudibleBars", "metronome.gapSilentBars"] {
            let row = element(id, app)
            reveal(row, app)
            let down = row.buttons["Decrement"]
            for _ in 0..<3 where down.exists && down.isEnabled { down.tap() }
        }
        app.buttons["Done"].tap()
        element("metronome.toggle", app).tap()
        let phase = element("metronome.gapPhase", app)
        XCTAssertTrue(waitForLabel(phase, containing: "Silent", timeout: 50))
        XCTAssertTrue(app.staticTexts["Keep the pulse"].exists)
        XCTAssertTrue(waitForLabel(phase, containing: "Clicks", timeout: 50))
        element("metronome.toggle", app).tap()
        XCTAssertTrue(element("metronome.toggle", app).label.contains("Start"))
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Physical gap trainer after a complete audible-silent cycle"
        proof.lifetime = .keepAlways
        add(proof)
        app.terminate()
#endif
    }

    @MainActor
    func testGapTrainerCyclesSilentlyAndPersists() throws {
        let app = launch()
        openMetronome(app)
        element("metronome.settings", app).tap()
        let toggle = element("metronome.gapEnabled", app)
        reveal(toggle, app)
        setSwitch(toggle, enabled: true)
        XCTAssertTrue(element("metronome.gapAudibleBars", app).exists)
        XCTAssertTrue(element("metronome.gapSilentBars", app).exists)
        app.buttons["Done"].tap()
        reveal(element("metronome.toggle", app), app)
        element("metronome.toggle", app).tap()
        let phase = element("metronome.gapPhase", app)
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(phase, containing: "Silent", timeout: 15))
        XCTAssertTrue(app.staticTexts["Keep the pulse"].exists)
        XCTAssertTrue(waitForLabel(phase, containing: "Clicks", timeout: 10))
        element("metronome.toggle", app).tap()
        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        enterGuest(app)
        openMetronome(app)
        element("metronome.settings", app).tap()
        let restored = element("metronome.gapEnabled", app)
        reveal(restored, app)
        XCTAssertEqual(restored.value as? String, "1")
    }

    @MainActor
    func testIntonationHistoryExcludesSamplesAndCreatesOneGoal() throws {
        var app = launch()
        openHistory(app)
        XCTAssertTrue(app.staticTexts["More evidence needed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Explore sustained tone"].exists)
        app.terminate()
        app = launch(extra: ["UITEST_INTONATION_HISTORY"])
        openHistory(app)
        let create = element("intonationHistory.goal.C4", app)
        reveal(create, app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Above equal temperament")).firstMatch.exists)
        create.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Practice goals"].tap()
        XCTAssertTrue(element("screen.practiceGoals", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practiceGoals.logAttempt.")).count, 1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Listen first")).firstMatch.exists)
        let keepPracticing = app.buttons["Keep practicing"]
        if keepPracticing.waitForExistence(timeout: 3) { keepPracticing.tap() }
        let back = app.navigationBars.buttons["Intonation history"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(element("screen.intonationHistory", app).waitForExistence(timeout: 5))
        reveal(element("intonationHistory.goal.C4", app), app)
        element("intonationHistory.goal.C4", app).tap()
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "already exists")).firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Practice goals"].tap()
        XCTAssertTrue(element("screen.practiceGoals", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practiceGoals.logAttempt.")).count, 1)
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_FIXTURES", "UITEST_RESET_STATE"] + extra
        app.launch()
        XCTAssertTrue(element("screen.practice", app).waitForExistence(timeout: 8))
        return app
    }

    @MainActor private func enterGuest(_ app: XCUIApplication) {
        let guest = element("gateway.continueAsGuest", app)
        if guest.waitForExistence(timeout: 5) { guest.tap() }
        let setup = element("onboarding.startPractice", app)
        if setup.waitForExistence(timeout: 2) { setup.tap() }
        XCTAssertTrue(element("screen.practice", app).waitForExistence(timeout: 8))
    }

    @MainActor private func openMetronome(_ app: XCUIApplication) {
        let link = element("practice.metronome", app)
        reveal(link, app); link.tap()
        XCTAssertTrue(element("screen.metronome", app).waitForExistence(timeout: 5))
    }

    @MainActor private func openHistory(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == %@", "Progress")).firstMatch.tap()
        let link = element("progress.intonationHistory", app)
        reveal(link, app); link.tap()
        XCTAssertTrue(element("screen.intonationHistory", app).waitForExistence(timeout: 5))
    }

    @MainActor private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<18 {
            if target.exists && target.isHittable { return }
            let candidates = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let scroll = candidates.last(where: { $0.isHittable }) ?? candidates.last else {
                XCTFail("Expected a scrollable screen"); return
            }
            let above = target.exists && target.frame.maxY < scroll.frame.minY + 60
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: above ? 0.3 : 0.7))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: above ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let detail = XCTAttachment(string: app.debugDescription)
        detail.lifetime = .keepAlways
        add(detail)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(target.exists && target.isHittable, "Control must be reachable")
    }

    @MainActor private func setSwitch(_ row: XCUIElement, enabled: Bool) {
        let desired = enabled ? "1" : "0"
        guard row.value as? String != desired else { return }
        let nested = row.descendants(matching: .switch).firstMatch
        (nested.exists ? nested : row).tap()
        XCTAssertEqual(row.value as? String, desired)
    }

    @MainActor private func waitForLabel(_ target: XCUIElement, containing text: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: target)], timeout: timeout) == .completed
    }
}
