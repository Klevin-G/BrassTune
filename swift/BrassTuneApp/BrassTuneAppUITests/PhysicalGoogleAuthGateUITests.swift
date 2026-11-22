import XCTest

/// Opt-in physical-iPhone harness for the production Google sign-in gate.
/// It drives the already-installed production app by bundle identifier and
/// never passes test-fixture or reset arguments, so app data is untouched.
/// Skipped unless the runner receives BRASSTUNE_PHYSICAL_GATE=1
/// (xcodebuild: TEST_RUNNER_BRASSTUNE_PHYSICAL_GATE=1).
///
/// The harness never types into Google. It selects an account that Safari
/// already knows, taps provider consent, and stops with a precise failure if
/// Google asks for a password, a verification step, or the app asks for
/// profile data. Attachments are kept only on failure because web screens
/// may show the account address; recorded outcomes are value-free.
final class PhysicalGoogleAuthGateUITests: XCTestCase {
    private static let productionBundleIdentifier = "com.aryasalem.BrassTune"

    @MainActor private var app: XCUIApplication { XCUIApplication(bundleIdentifier: Self.productionBundleIdentifier) }
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    @MainActor private var safariViewService: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.SafariViewService") }

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("The Google auth gate requires a physical iPhone.")
        #else
        guard ProcessInfo.processInfo.environment["BRASSTUNE_PHYSICAL_GATE"] == "1" else {
            throw XCTSkip("Set BRASSTUNE_PHYSICAL_GATE=1 to run the physical Google auth gate.")
        }
        #endif
    }

    @MainActor
    func testInstalledProductionAppActivatesForAutomation() throws {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        record("production_app_foreground=true")
        attachFailureScreen("production-app-foreground")
    }

    /// Step 1: real Google sign-in from a signed-out production app.
    @MainActor
    func testGoogleSignInCompletesInProductionApp() throws {
        coldLaunch()
        try beginGoogleSignIn()
        try completeGoogleAuthorization()
        try assertReturnedSignedIn()
        record("google_sign_in=returned_signed_in")
    }

    /// Step 2: a cold launch restores the Keychain session without sign-in.
    @MainActor
    func testColdLaunchRestoresSignedInSession() throws {
        coldLaunch()
        XCTAssertFalse(gateway.waitForExistence(timeout: 8), "Cold launch showed the signed-out gateway")
        try assertSettingsShowsSignedIn()
        record("cold_launch=restored_signed_in")
    }

    /// Step 3: sign out, then a cold launch stays signed out.
    @MainActor
    func testSignOutThenColdLaunchStaysSignedOut() throws {
        coldLaunch()
        try openSettings()
        let signOut = app.buttons.matching(identifier: "settings.signOut").firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 10), "Sign out is unavailable")
        signOut.tap()
        XCTAssertTrue(gateway.waitForExistence(timeout: 20), "Sign out did not return to the gateway")
        coldLaunch()
        XCTAssertTrue(gateway.waitForExistence(timeout: 15), "Signed-out cold launch did not show the gateway")
        record("sign_out=gateway;signed_out_cold_launch=gateway")
    }

    /// Step 4: cancelling the browser sheet is reported as cancellation, the
    /// app stays retryable, and a second real sign-in succeeds.
    @MainActor
    func testGoogleCancelThenRetrySucceeds() throws {
        coldLaunch()
        try beginGoogleSignIn()
        try cancelBrowserSheet()
        let notice = element("gateway.authNotice")
        if notice.waitForExistence(timeout: 10) {
            XCTAssertFalse(
                notice.label.contains("could not be verified"),
                "Cancellation surfaced the callback-verification error"
            )
        }
        let google = element("gateway.authGoogleSignIn")
        XCTAssertTrue(google.waitForExistence(timeout: 10), "Google sign-in was not retryable after cancel")
        google.tap()
        try completeGoogleAuthorization()
        try assertReturnedSignedIn()
        record("cancel=retryable;second_google_sign_in=returned_signed_in")
    }

    // MARK: - Steps

    @MainActor private var gateway: XCUIElement { element("screen.gateway") }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func coldLaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    @MainActor
    private func beginGoogleSignIn() throws {
        let signIn = element("gateway.signIn")
        guard signIn.waitForExistence(timeout: 15) else {
            attachFailureScreen("no-gateway-sign-in")
            throw failure("The production app is not on the signed-out gateway")
        }
        signIn.tap()
        let google = element("gateway.authGoogleSignIn")
        guard google.waitForExistence(timeout: 20) else {
            attachFailureScreen("no-google-button")
            throw failure("Google sign-in is not offered")
        }
        google.tap()
    }

    /// Accepts the system web-authentication prompt, then selects an
    /// existing Google account and provider consent without typing.
    @MainActor
    private func completeGoogleAuthorization() throws {
        acceptSystemAuthenticationPrompt()
        let deadline = Date().addingTimeInterval(120)
        var accountChosen = false
        while Date() < deadline {
            if appReturnedFromBrowser() { return }
            for host in [app, safariViewService] {
                let web = host.webViews.firstMatch
                guard web.exists else { continue }
                // Only the web page counts: the app's own sign-in sheet has a
                // separate email/password form behind the browser sheet.
                if web.secureTextFields.count > 0 {
                    attachFailureScreen("google-requires-password")
                    throw failure("HUMAN ACTION: Google requires a password; the harness never types credentials")
                }
                let verification = web.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'Verify it' OR label CONTAINS[c] '2-Step'")
                ).firstMatch
                if verification.exists {
                    attachFailureScreen("google-verification")
                    throw failure("HUMAN ACTION: Google requires account verification on the phone")
                }
                if web.textFields.count > 0, !accountChosen,
                   web.links.matching(NSPredicate(format: "label CONTAINS '@'")).count == 0 {
                    attachFailureScreen("google-requires-email")
                    throw failure("HUMAN ACTION: no Google account is signed in to Safari; the harness never types credentials")
                }
                let account = web.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS '@' AND (elementType == %d OR elementType == %d)",
                                          XCUIElement.ElementType.link.rawValue,
                                          XCUIElement.ElementType.button.rawValue))
                    .firstMatch
                if !accountChosen, account.exists, account.isHittable {
                    account.tap()
                    accountChosen = true
                    continue
                }
                for label in ["Continue", "Allow"] {
                    let consent = web.buttons[label]
                    if consent.exists, consent.isHittable {
                        consent.tap()
                        break
                    }
                }
            }
            acceptSystemAuthenticationPrompt()
            Thread.sleep(forTimeInterval: 1)
        }
        attachFailureScreen("google-timeout")
        throw failure("Google authorization did not return to the app within 120 seconds")
    }

    @MainActor
    private func acceptSystemAuthenticationPrompt() {
        let continueButton = springboard.alerts.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }
    }

    /// Cancels at the system "Wants to Use … to Sign In" prompt, which is the
    /// user-cancel path of ASWebAuthenticationSession. A Google account that
    /// already approved the app can finish in about a second once the sheet
    /// opens, so cancelling inside the sheet would race the callback.
    @MainActor
    private func cancelBrowserSheet() throws {
        let systemCancel = springboard.alerts.buttons["Cancel"]
        if systemCancel.waitForExistence(timeout: 10) {
            systemCancel.tap()
            record("cancel_point=system_prompt")
            return
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            for host in [app, safariViewService] {
                guard host.webViews.firstMatch.exists else { continue }
                for label in ["Cancel", "Close", "Done"] {
                    let cancel = host.buttons[label]
                    if cancel.exists, cancel.isHittable {
                        cancel.tap()
                        record("cancel_point=browser_sheet")
                        return
                    }
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        attachFailureScreen("no-cancel")
        throw failure("The authentication sheet offered no Cancel control")
    }

    /// Checks only the app's own screens. Querying the browser service while
    /// the authentication sheet is being torn down can stall XCUITest.
    @MainActor
    private func appReturnedFromBrowser() -> Bool {
        app.tabBars.firstMatch.exists
            || element("gateway.authNotice").exists
            || element("screen.profileEditor").exists
            || element("onboarding.hero").exists
            || element("screen.instrumentSetup").exists
    }

    @MainActor
    private func assertReturnedSignedIn() throws {
        let notice = element("gateway.authNotice")
        if notice.waitForExistence(timeout: 3), gateway.exists {
            // The auth notice text is a fixed localized app message, never a
            // provider value, so it is safe to report verbatim.
            record("auth_notice=\(notice.label)")
            attachFailureScreen("auth-notice")
            throw failure("Sign-in returned an error notice: \(notice.label)")
        }
        if element("screen.profileEditor").waitForExistence(timeout: 5) {
            record("profile_editor_required=true")
            throw failure("HUMAN ACTION: the signed-in account requires profile details before continuing")
        }
        try assertSettingsShowsSignedIn()
    }

    /// First-run onboarding and the microphone rationale are dismissed with
    /// their "Not now" controls; neither changes account or practice data.
    @MainActor
    private func dismissFirstRunPromptsIfShown() {
        for identifier in ["onboarding.startPractice", "onboarding.cancel", "microphone.rationaleNotNow"] {
            let control = app.buttons.matching(identifier: identifier).firstMatch
            if control.waitForExistence(timeout: 3), control.isHittable {
                control.tap()
            }
        }
    }

    @MainActor
    private func openSettings() throws {
        dismissFirstRunPromptsIfShown()
        let more = app.tabBars.buttons["More"]
        guard more.waitForExistence(timeout: 20) else {
            attachFailureScreen("no-tab-bar")
            throw failure("The main tab bar did not appear")
        }
        more.tap()
        let settings = app.buttons.matching(identifier: "more.settings").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(element("screen.settings").waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertSettingsShowsSignedIn() throws {
        try openSettings()
        let status = element("settings.accountStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        // The signed-in pill shows the account address. Assert its shape only.
        let signedIn = status.label.contains("@")
        record("settings_signed_in=\(signedIn)")
        XCTAssertTrue(signedIn, "Settings does not show a signed-in account")
        XCTAssertTrue(element("settings.signOut").exists, "Signed-in settings has no sign-out control")
    }

    // MARK: - Evidence

    private func record(_ outcome: String) {
        let attachment = XCTAttachment(string: outcome)
        attachment.name = "outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
        NSLog("BrassTune physical gate outcome: %@", outcome)
    }

    @MainActor
    private func attachFailureScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
    }

    private func failure(_ message: String) -> Error {
        NSError(domain: "BrassTunePhysicalGate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Opt-in physical-iPhone evidence for the Tuner's real microphone lifecycle.
/// It defaults to the installed development bundle and touches neither account
/// nor recording data. Set BRASSTUNE_PHYSICAL_MIC_TARGET_PRODUCTION=1 only to
/// compare the released production baseline.
final class PhysicalMicrophoneRecoveryUITests: XCTestCase {
    private static let developmentBundleIdentifier = "com.aryasalem.BrassTune.dev"
    private static let productionBundleIdentifier = "com.aryasalem.BrassTune"

    @MainActor private var app: XCUIApplication {
        XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    }

    private var targetBundleIdentifier: String {
        ProcessInfo.processInfo.environment["BRASSTUNE_PHYSICAL_MIC_TARGET_PRODUCTION"] == "1"
            ? Self.productionBundleIdentifier
            : Self.developmentBundleIdentifier
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("The microphone recovery gate requires a physical iPhone.")
#else
        guard ProcessInfo.processInfo.environment["BRASSTUNE_PHYSICAL_MIC_GATE"] == "1" else {
            throw XCTSkip("Set BRASSTUNE_PHYSICAL_MIC_GATE=1 to run the physical microphone recovery gate.")
        }
#endif
    }

    @MainActor
    func testPhysicalTunerMicrophoneStartStopAndForegroundRecovery() throws {
        app.activate()
        require(app.wait(for: .runningForeground, timeout: 20), "The target BrassTune bundle did not enter the foreground.")
        enterGuestOnlyIfSignedOut()
        dismissOnboardingIfPresented()
        openTuner()

        startTunerListeningIfNeeded()
        allowMicrophonePermissionIfPresented()
        let readout = element("tuner.readout")
        let take = element("tuner.take")
        let stop = element("tuner.floating.stop")
        require(readout.waitForExistence(timeout: 15), "The Tuner readout did not appear.")
        require(take.waitForExistence(timeout: 20), "Live Tuner controls did not appear after microphone authorization.")
        require(stop.exists, "Live Tuner stop control did not appear after microphone authorization.")
        require(waitForLiveReadout(readout), "The Tuner did not reach a live microphone state after startup.")

        stop.tap()
        let startListening = element("tuner.recordButton")
        require(startListening.waitForExistence(timeout: 15), "Stopping Tuner listening did not expose the start control.")
        startListening.tap()
        require(stop.waitForExistence(timeout: 20), "Tuner did not restart listening after an explicit stop.")

        XCUIDevice.shared.press(.home)
        require(app.wait(for: .runningBackground, timeout: 15), "The app did not background for the foreground recovery check.")
        app.activate()
        require(app.wait(for: .runningForeground, timeout: 20), "The app did not return to the foreground.")
        require(stop.waitForExistence(timeout: 20), "Tuner did not recover live listening after foregrounding.")
        require(waitForLiveReadout(readout), "Foreground recovery did not reach a live microphone state.")
        stop.tap()
    }

    @MainActor
    func testPhysicalTunerHierarchyDiagnostic() throws {
        app.activate()
        require(app.wait(for: .runningForeground, timeout: 20), "The target BrassTune bundle did not enter the foreground.")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Tuner launch hierarchy diagnostic"
        hierarchy.lifetime = .deleteOnSuccess
        add(hierarchy)
    }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor private func enterGuestOnlyIfSignedOut() {
        guard element("screen.gateway").waitForExistence(timeout: 5) else { return }
        let guest = element("gateway.continueAsGuest")
        require(guest.waitForExistence(timeout: 10), "The signed-out gateway has no guest continuation.")
        guest.tap()
    }

    @MainActor private func dismissOnboardingIfPresented() {
        let startPractice = element("onboarding.startPractice")
        if startPractice.waitForExistence(timeout: 8) { startPractice.tap() }
    }

    @MainActor private func openTuner() {
        let tuner = app.tabBars.buttons["Tuner"].exists
            ? app.tabBars.buttons["Tuner"]
            : app.descendants(matching: .button).matching(NSPredicate(format: "label == %@", "Tuner")).firstMatch
        require(tuner.waitForExistence(timeout: 15), "The primary Tuner tab is unavailable.")
        tuner.tap()
        require(element("screen.tuner").waitForExistence(timeout: 15), "Tuner did not open.")
    }

    @MainActor private func startTunerListeningIfNeeded() {
        let startListening = element("tuner.recordButton")
        guard startListening.waitForExistence(timeout: 3) else { return }
        startListening.tap()

        let rationaleContinue = element("microphone.rationaleContinue")
        if rationaleContinue.waitForExistence(timeout: 8) {
            rationaleContinue.tap()
        }
    }

    @MainActor private func allowMicrophonePermissionIfPresented() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Allow")).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    @MainActor private func waitForLiveReadout(_ readout: XCUIElement) -> Bool {
        let liveState = NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
            "Listening — no signal",
            "Finding your note",
            "Signal locked"
        )
        let expectation = XCTNSPredicateExpectation(predicate: liveState, object: readout)
        return XCTWaiter().wait(for: [expectation], timeout: 20) == .completed
    }

    @MainActor private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            preserveFailureScreen(named: "physical-microphone-recovery-failure")
            XCTFail(message)
            return
        }
    }

    @MainActor private func preserveFailureScreen(named: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = named
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
