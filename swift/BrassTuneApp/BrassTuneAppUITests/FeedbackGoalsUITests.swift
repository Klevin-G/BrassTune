import XCTest

final class FeedbackGoalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGuestCanCreateAssessCompleteReopenAndPersistPracticeGoal() throws {
        let app = launchFixtureApp(reset: true)
        let goals = element("practice.goals", in: app)
        XCTAssertTrue(goals.waitForExistence(timeout: 8))
        goals.tap()
        XCTAssertTrue(element("screen.practiceGoals", in: app).waitForExistence(timeout: 5))

        let create = app.buttons["practiceGoals.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let passage = app.textFields["practiceGoals.passage"]
        replaceText(in: passage, with: "Arban No. 1")
        app.navigationBars.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Arban No. 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "clean repetitions", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "80", in: app).exists)
        XCTAssertTrue(element(containing: "Strategy: Slow practice", in: app).exists)
        attachScreenshot(of: app, named: "Guest measurable practice goal")

        let backToPractice = app.navigationBars.buttons["Practice"]
        XCTAssertTrue(backToPractice.waitForExistence(timeout: 3))
        backToPractice.tap()
        let reviewGoal = element("practice.reviewGoal", in: app)
        XCTAssertTrue(reviewGoal.waitForExistence(timeout: 5), "Practice Home must surface an active goal review action.")
        XCTAssertTrue(reviewGoal.isHittable)
        reviewGoal.tap()
        XCTAssertTrue(element("screen.practiceGoals", in: app).waitForExistence(timeout: 5))

        let logAttempt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practiceGoals.logAttempt.")).firstMatch
        XCTAssertTrue(logAttempt.waitForExistence(timeout: 5))
        logAttempt.tap()
        chooseOutcome("Improving", in: app)
        let reflection = element("practiceGoals.reflection", in: app)
        bringIntoView(reflection, in: app)
        replaceText(in: reflection, with: "Attacks spoke clearly.")
        dismissKeyboard(in: app)
        let nextAdjustment = element("practiceGoals.nextAdjustment", in: app)
        bringIntoView(nextAdjustment, in: app)
        replaceText(in: nextAdjustment, with: "Keep the air moving.")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Latest self-assessment: Improving"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reflection: Attacks spoke clearly."].exists)
        XCTAssertFalse(element(containing: "Self-reported:", in: app).exists, "A narrative-only attempt must not invent measurements.")

        logAttempt.tap()
        chooseOutcome("Not yet", in: app)
        let measurements = element("practiceGoals.recordMeasurements", in: app)
        bringIntoView(measurements, in: app)
        // iOS 26 exposes the full Form row as a switch and the actual toggle
        // as a nested switch. Tap the control rather than the row's label.
        let measurementToggle = measurements.descendants(matching: .switch).firstMatch
        if measurementToggle.exists { measurementToggle.tap() } else { measurements.tap() }
        XCTAssertEqual(measurements.value as? String, "1")
        let measurementState = XCTAttachment(string: app.debugDescription)
        measurementState.name = "Goal measurements control state"
        measurementState.lifetime = .deleteOnSuccess
        add(measurementState)
        let repetitions = element(containing: "Clean repetitions: 0", in: app)
        XCTAssertTrue(repetitions.waitForExistence(timeout: 3))
        let zeroReflection = element("practiceGoals.reflection", in: app)
        bringIntoView(zeroReflection, in: app)
        replaceText(in: zeroReflection, with: "No full repetition today.")
        dismissKeyboard(in: app)
        let zeroAdjustment = element("practiceGoals.nextAdjustment", in: app)
        bringIntoView(zeroAdjustment, in: app)
        replaceText(in: zeroAdjustment, with: "Return to one note.")
        dismissKeyboard(in: app)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Latest self-assessment: Not yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Self-reported: 0 repetitions", in: app).exists)
        XCTAssertFalse(element(containing: "30 BPM", in: app).exists)

        let complete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practiceGoals.complete.")).firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(app.staticTexts["Completed manually"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reopen"].exists)
        app.buttons["Reopen"].tap()
        XCTAssertFalse(app.staticTexts["Completed manually"].exists)

        openTab("Progress", in: app)
        let outcomes = app.staticTexts["Practice outcomes"]
        XCTAssertTrue(outcomes.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Arban No. 1"].exists)
        XCTAssertTrue(element(containing: "Self-reported: 0 repetitions", in: app).exists)
        let activity = app.staticTexts["Activity"]
        XCTAssertTrue(activity.exists)
        XCTAssertLessThan(outcomes.frame.minY, activity.frame.minY, "Outcomes must precede activity totals.")

        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        XCTAssertTrue(element("screen.gateway", in: app).waitForExistence(timeout: 8))
        element("gateway.continueAsGuest", in: app).tap()
        let resumePractice = app.buttons["onboarding.startPractice"]
        if resumePractice.waitForExistence(timeout: 3) { resumePractice.tap() }
        XCTAssertTrue(element("screen.practice", in: app).waitForExistence(timeout: 8))
        element("practice.goals", in: app).tap()
        XCTAssertTrue(app.staticTexts["Arban No. 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Latest self-assessment: Not yet"].exists)
        XCTAssertTrue(app.buttons["Complete"].exists, "Reopened goal must stay reopened after relaunch.")
        XCTAssertTrue(element(containing: "Self-reported: 0 repetitions", in: app).exists)
        let tempoAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "practiceGoals.practiceTempo.")).firstMatch
        bringIntoView(tempoAction, in: app)
        tempoAction.tap()
        XCTAssertTrue(element("screen.metronome", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "80", in: app).exists)
        XCTAssertTrue(element("metronome.toggle", in: app).label.contains("Start"), "Opening a goal tool must not start sound.")
    }

    @MainActor
    func testTunerAndMetronomePracticeTipsPresentGuidance() throws {
        let app = launchFixtureApp(reset: true)

        openTab("Tuner", in: app)
        let tunerTip = app.buttons["tuner.practiceTip"]
        XCTAssertTrue(tunerTip.waitForExistence(timeout: 5))
        tunerTip.tap()
        XCTAssertTrue(element("practice.toolGuidance", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tune by listening first"].exists)
        XCTAssertTrue(app.staticTexts["Use the tuner to check a note after listening to it yourself."].exists)
        XCTAssertTrue(app.staticTexts["Listen for a steady pitch instead of chasing every movement of the needle."].exists)
        app.buttons["Done"].tap()

        openTab("Practice", in: app)
        let metronome = element("practice.metronome", in: app)
        XCTAssertTrue(metronome.waitForExistence(timeout: 5))
        metronome.tap()
        let metronomeTip = app.buttons["metronome.practiceTip"]
        XCTAssertTrue(metronomeTip.waitForExistence(timeout: 5))
        metronomeTip.tap()
        XCTAssertTrue(element("practice.toolGuidance", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build a steady pulse"].exists)
        XCTAssertTrue(app.staticTexts["Use the metronome to check the pulse of a short passage at a comfortable tempo."].exists)
        XCTAssertTrue(app.staticTexts["Listen for evenly spaced attacks and a steady pulse when the click stops."].exists)
    }

    @MainActor
    func testWelcomeAccountAndGuestReentryAreReachableAndCaptured() throws {
        let app = launchWelcomeApp(extraArguments: [])
        captureGatewayBaseline(in: app, named: "Light welcome normal")

        let createAccount = element("gateway.createAccount", in: app)
        XCTAssertTrue(waitForStableHittability(of: createAccount, in: app))
        let guest = element("gateway.continueAsGuest", in: app)
        XCTAssertTrue(waitForStableHittability(of: guest, in: app))
        XCTAssertGreaterThanOrEqual(guest.frame.height, 44)
        createAccount.tap()
        XCTAssertTrue(element("gateway.email", in: app).waitForExistence(timeout: 5))
        exitAccountFormAndReachPractice(in: app)
        app.terminate()
        app.launchArguments = ["UITEST_AUTH_EMPTY"]
        app.launch()
        assertGuestReentry(in: app)
    }

    @MainActor
    func testWelcomeArabicMaximumDynamicTypeActionsRemainReachable() throws {
        let app = launchWelcomeApp(extraArguments: [
            "UITEST_RTL",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleLanguages",
            "(ar)",
            "-AppleLocale",
            "ar",
        ])
        captureGatewayBaseline(in: app, named: "Light welcome Arabic XXXL")

        let createAccount = element("gateway.createAccount", in: app)
        XCTAssertTrue(waitForStableHittability(of: createAccount, in: app))
        XCTAssertGreaterThanOrEqual(createAccount.frame.height, 44)
        let guest = element("gateway.continueAsGuest", in: app)
        XCTAssertTrue(waitForStableHittability(of: guest, in: app))
        XCTAssertGreaterThanOrEqual(guest.frame.height, 44)
        XCTAssertTrue(bringGatewayControlIntoView(createAccount, in: app))
        captureGatewayBaseline(in: app, named: "Arabic XXXL account action before tap")
        createAccount.tap()
        let email = element("gateway.email", in: app)
        // The bottom guest escape and email rows are lazily created by Form.
        // The sheet's navigation bar exists before either row is scrolled in.
        let accountForm = app.navigationBars.firstMatch
        guard accountForm.waitForExistence(timeout: 5) else {
            captureGatewayBaseline(in: app, named: "Arabic XXXL account sheet timeout")
            XCTFail("Create account must present its account form at Accessibility XXXL.")
            return
        }
        captureGatewayBaseline(in: app, named: "Arabic XXXL account sheet before email scroll")
        guard revealEmailInAccountForm(email, in: app) else {
            captureGatewayBaseline(in: app, named: "Arabic XXXL account email timeout")
            XCTFail("Create account form must make its email field reachable at Accessibility XXXL.")
            return
        }
        exitAccountFormAndReachPractice(in: app)
    }

    @MainActor
    func testGatewayCreditsModalHasPhotoAndDismissesInNormalAndRTL() throws {
        for (index, arguments) in [
            [],
            ["UITEST_RTL", "-AppleLanguages", "(ar)", "-AppleLocale", "ar"],
        ].enumerated() {
            let app = launchWelcomeApp(extraArguments: arguments)
            let credits = element("gateway.credits", in: app)
            XCTAssertTrue(waitForStableHittability(of: credits, in: app))
            credits.tap()
            let done = app.buttons["gateway.creditsDone"]
            XCTAssertTrue(done.waitForExistence(timeout: 5), "Credits must present its modal before verification.")
            captureGatewayBaseline(in: app, named: index == 0 ? "Credits normal modal" : "Credits Arabic modal")

            let photoCredit = element(containing: "Trumpet 001", in: app)
            XCTAssertTrue(waitForExistence(of: photoCredit, in: app))
            XCTAssertTrue(waitForExistence(of: element(containing: "CC BY 2.0", in: app), in: app))
            XCTAssertTrue(done.isHittable, "Credits Done must remain tappable after the credit content is visible.")
            done.tap()
            XCTAssertTrue(element("screen.gateway", in: app).waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testFirstPracticeGuideRoutesToStoppedToolsAndFinishes() throws {
        let app = launchFixtureApp(reset: true)
        let guide = element("practice.firstGuide", in: app)
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        XCTAssertTrue(element("screen.firstPractice", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1. Find a comfortable note"].exists)

        element("firstPractice.tuner", in: app).tap()
        XCTAssertTrue(element("screen.tuner", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons["First practice"].tap()
        XCTAssertTrue(element("screen.firstPractice", in: app).waitForExistence(timeout: 5))
        element("firstPractice.next", in: app).tap()
        XCTAssertTrue(app.staticTexts["2. Play with a steady pulse"].exists)
        element("firstPractice.metronome", in: app).tap()
        XCTAssertTrue(element("screen.metronome", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("metronome.toggle", in: app).label.contains("Start"))
        app.navigationBars.buttons["First practice"].tap()
        element("firstPractice.next", in: app).tap()
        XCTAssertTrue(app.staticTexts["Practice complete"].exists)
        element("firstPractice.finish", in: app).tap()
        XCTAssertTrue(element("screen.practice", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testDroneListeningExerciseChangesThirdAndFifthWithoutStartingTone() throws {
        let app = launchFixtureApp(reset: true)
        let drone = element("practice.drone", in: app)
        bringIntoView(drone, in: app)
        drone.tap()
        XCTAssertTrue(element("screen.droneInterval", in: app).waitForExistence(timeout: 5))

        for (title, offset) in [("Major third", "-14"), ("Perfect fifth", "+2")] {
            let choice = app.buttons[title]
            bringIntoView(choice, in: app)
            choice.tap()
            XCTAssertEqual(element("drone.interval", in: app).value as? String, title)
            XCTAssertTrue(element(containing: "Just interval: \(offset) cents", in: app).exists)
            XCTAssertTrue(element("drone.toggle", in: app).label.contains("Play"),
                          "Selecting a listening exercise must not start audio.")
        }
        attachScreenshot(of: app, named: "Third and fifth listening choices")
    }

    @MainActor
    func testPracticeGoalTempoLadderOpensMetronomeAtChosenStepStopped() throws {
        let app = launchFixtureApp(reset: true)
        element("practice.goals", in: app).tap()
        app.buttons["practiceGoals.create"].tap()
        replaceText(in: element("practiceGoals.passage", in: app), with: "Tempo ladder check")
        app.navigationBars.buttons["Save"].tap()

        let disclosure = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "practiceGoals.ladderDisclosure."
        )).firstMatch
        bringIntoView(disclosure, in: app)
        disclosure.tap()
        let next = app.buttons["Next tempo"]
        bringIntoView(next, in: app)
        XCTAssertTrue(next.isEnabled)
        let initial = element(containing: "Current:", in: app).label
        next.tap()
        let advanced = element(containing: "Current:", in: app).label
        XCTAssertNotEqual(initial, advanced)
        let back = app.buttons["Step back"]
        XCTAssertTrue(back.isEnabled)
        let practice = app.buttons.matching(NSPredicate(
            format: "label MATCHES %@", "Practice at [0-9]+ BPM"
        )).firstMatch
        bringIntoView(practice, in: app)
        let selectedTempo = practice.label
        practice.tap()
        XCTAssertTrue(element("screen.metronome", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("metronome.toggle", in: app).label.contains("Start"))
        let bpm = element("metronome.bpm", in: app)
        XCTAssertTrue(bpm.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedTempo.contains(bpm.label.filter(\.isNumber)),
                      "The chosen ladder step must be the metronome tempo.")
    }

    @MainActor
    func testFixtureScoreCreatesPrefilledPracticeGoal() throws {
        let app = launchFixtureApp(reset: true)
        let scores = element("practice.sheetMusic", in: app)
        bringIntoView(scores, in: app)
        scores.tap()
        XCTAssertTrue(element("screen.scorePractice", in: app).waitForExistence(timeout: 5))
        element("score.import.testFixture", in: app).tap()
        let scoreTitle = element("score.card", in: app)
        XCTAssertTrue(scoreTitle.waitForExistence(timeout: 5))
        let title = scoreTitle.label
        let create = element("score.createPracticeGoal", in: app)
        bringIntoView(create, in: app)
        create.tap()
        let passage = element("practiceGoals.passage", in: app)
        XCTAssertTrue(passage.waitForExistence(timeout: 5))
        XCTAssertTrue((passage.value as? String ?? "").contains(title))
        app.navigationBars.buttons["Save"].tap()
        app.navigationBars.buttons["Practice"].tap()
        let goals = element("practice.goals", in: app)
        bringIntoView(goals, in: app)
        goals.tap()
        XCTAssertTrue(element(containing: title, in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchFixtureApp(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset ? ["UITEST_FIXTURES", "UITEST_RESET_STATE"] : ["UITEST_FIXTURES"]
        app.launch()
        XCTAssertTrue(element("screen.practice", in: app).waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private var welcomeAccountEnvironment: [String: String] {
        [
            "BRASSTUNE_ENV": "production",
            "BRASSTUNE_API_BASE_URL": "https://brasstune-u8qj.onrender.com",
            "BRASSTUNE_SUPABASE_URL": "https://project.supabase.co",
            "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
        ]
    }

    @MainActor
    private func launchWelcomeApp(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-brassTune.colorTheme", "light", "UITEST_RESET_STATE", "UITEST_ENTRY_FLOW", "UITEST_AUTH_EMPTY"] + extraArguments
        app.launchEnvironment = welcomeAccountEnvironment
        app.launch()
        XCTAssertTrue(element("screen.gateway", in: app).waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func enterGuestAndReachPractice(in app: XCUIApplication) {
        let guest = element("gateway.continueAsGuest", in: app)
        XCTAssertTrue(waitForStableHittability(of: guest, in: app))
        XCTAssertGreaterThanOrEqual(guest.frame.height, 44)
        guest.tap()
        let startPractice = app.buttons["onboarding.startPractice"]
        if startPractice.waitForExistence(timeout: 3) {
            XCTAssertTrue(waitForStableHittability(of: startPractice, in: app))
            startPractice.tap()
        }
        XCTAssertTrue(element("screen.practice", in: app).waitForExistence(timeout: 8))
    }

    @MainActor
    private func exitAccountFormAndReachPractice(in app: XCUIApplication) {
        let escape = element("gateway.authGuestEscape", in: app)
        XCTAssertTrue(waitForStableHittability(of: escape, in: app))
        escape.tap()
        let startPractice = app.buttons["onboarding.startPractice"]
        if startPractice.waitForExistence(timeout: 3) {
            XCTAssertTrue(waitForStableHittability(of: startPractice, in: app))
            startPractice.tap()
        }
        XCTAssertTrue(element("screen.practice", in: app).waitForExistence(timeout: 8))
    }

    @MainActor
    private func assertGuestReentry(in app: XCUIApplication) {
        let gateway = element("screen.gateway", in: app)
        let practice = element("screen.practice", in: app)
        for _ in 0..<8 {
            if practice.exists { return }
            if gateway.exists {
                enterGuestAndReachPractice(in: app)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("Cold guest reentry showed neither the local practice workspace nor a guest gateway.")
    }

    @MainActor
    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.waitForExistence(timeout: 3), tab.isHittable {
            tab.tap()
            return
        }
        let fallback = app.descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))
        fallback.tap()
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        if element.exists, element.isHittable { return }
        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.scrollViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3), "Expected a scrollable practice screen")
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            form.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected a reachable form field")
        XCTAssertTrue(element.isHittable, "Form field must be reachable on a compact iPhone")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = named
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func captureGatewayBaseline(in app: XCUIApplication, named: String) {
        attachScreenshot(of: app, named: named)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(named) accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func waitForStableHittability(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists, element.isHittable {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if element.exists, element.isHittable { return true }
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func waitForExistence(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        for _ in 0..<6 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) { return true }
        }
        return element.exists
    }

    @MainActor
    private func bringGatewayControlIntoView(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let viewport = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
        for _ in 0..<10 {
            if element.exists, element.isHittable {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if element.isHittable { return true }
            }
            let isAboveViewport = element.exists && element.frame.maxY < viewport.frame.minY
            if isAboveViewport {
                viewport.swipeDown()
            } else {
                viewport.swipeUp()
            }
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func revealEmailInAccountForm(_ email: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.collectionViews.firstMatch
        guard form.waitForExistence(timeout: 3) else { return false }
        for _ in 0..<10 {
            if email.exists, email.isHittable { return true }
            form.swipeUp()
        }
        return email.exists && email.isHittable
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["practiceGoals.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "The attempt editor must provide a visible keyboard dismissal control.")
        done.tap()
    }

    @MainActor
    private func chooseOutcome(_ title: String, in app: XCUIApplication) {
        let outcome = element("practiceGoals.outcome", in: app)
        bringIntoView(outcome, in: app)
        XCTAssertTrue(outcome.waitForExistence(timeout: 3), "The attempt editor must require a self-selected outcome.")
        outcome.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 3), "Expected outcome option \(title).")
        option.tap()
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        if let current = element.value as? String, !current.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(value)
    }
}
