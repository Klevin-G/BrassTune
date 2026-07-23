import XCTest
@testable import BrassTuneApp
import BrassTuneCore
import PDFKit
import Security
import UIKit

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let response: HTTPURLResponse
        let data: Data
        var delayNanoseconds: UInt64 = 0
    }

    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Stub)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let stub = try handler(request)
            if stub.delayNanoseconds > 0 {
                Thread.sleep(forTimeInterval: Double(stub.delayNanoseconds) / 1_000_000_000)
            }
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class InMemoryAuthSessionStore: @unchecked Sendable {
    var payload: String?
}

final class BrassTuneAppTests: XCTestCase {
    // MARK: - Shipping defaults and local model behavior

    @MainActor
    func testShippingDefaultsUseLiveMicrophoneAndAudibleMetronome() {
        XCTAssertFalse(NativeTestFixtures.areEnabled)
        XCTAssertEqual(NativeAudioEngine.defaultRecordingSource, .live)
        XCTAssertEqual(PracticeSessionSource.allCases, [.live])
        XCTAssertFalse(ScoreSourceKind.allCases.contains(.sample))

        let settings = MetronomeSettings()
        XCTAssertFalse(settings.muted)
        XCTAssertFalse(settings.visualOnly)
        XCTAssertEqual(settings.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testFixtureEntryPointsDoNothingWithoutUITestLaunchFlag() {
        let model = makeModel()

        model.startDemoRecording()
        model.stopDemoRecording()
        model.importSampleScore()

        XCTAssertEqual(model.recordingSource, .live)
        XCTAssertFalse(model.audioEngine.recording)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty)
    }

    @MainActor
    func testNoArgumentAccountDeletionClearsLocalState() async {
        let model = makeModel()
        model.sessions = [makeSession(name: "Test recording", cents: [-2, 0, 3])]

        await model.deleteAccount()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(model.lastError)
    }

    @MainActor
    func testSessionDeletionRemovesOnlySelectedSession() {
        let model = makeModel()
        let first = makeSession(name: "First", cents: [-2, 1, 6])
        let second = makeSession(name: "Second", cents: [9, 10, 11])
        model.sessions = [first, second]

        model.deleteSession(id: first.id)

        XCTAssertEqual(model.sessions, [second])
    }

    @MainActor
    func testLocalExportIncludesPracticeMetricsAndImportedScore() throws {
        let model = makeModel()
        model.sessions = [makeSession(name: "Exportable recording", cents: [-4, 0, 7])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Warm-up score")

        let export = model.exportDataText()

        XCTAssertTrue(export.contains("BrassTune local data export"))
        XCTAssertTrue(export.contains("Sessions: 1"))
        XCTAssertTrue(export.contains("Exportable recording"))
        XCTAssertTrue(export.contains("Average absolute cents"))
        XCTAssertTrue(export.contains("Cents preview"))
        XCTAssertTrue(export.contains("Scores: 1"))
        XCTAssertTrue(export.contains("Warm-up score"))
    }

    @MainActor
    func testAnalyticsSnapshotDerivesFromLocalSessions() {
        let model = makeModel()
        model.sessions = [
            makeSession(name: "Accurate", cents: [-2, 0, 3]),
            makeSession(name: "Sharp", cents: [9, 11, 7]),
        ]

        let analytics = model.analyticsSnapshot

        XCTAssertEqual(analytics.sessionCount, 2)
        XCTAssertEqual(analytics.validFrameCount, 6)
        XCTAssertEqual(analytics.bestSessionName, "Accurate")
        XCTAssertGreaterThan(analytics.averageAbsCents, 0)
        XCTAssertLessThan(analytics.averageInTunePercentage, 100)
    }

    @MainActor
    func testAccountFeaturesAreDisabledWithoutSupabaseConfig() {
        let model = makeModel()

        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertEqual(
            model.accountUnavailableMessage,
            "Online accounts aren't configured in this build. You can still practice as a guest, and your data stays on this device."
        )
    }

    @MainActor
    func testRuntimeAccountConfigFailsClosedUnlessURLAndPublishableKeyAreBothPresent() {
        let model = makeModel()
        let apiURL = AppConfig.approvedProductionAPIOrigin
        let supabaseURL = URL(string: "https://project.supabase.co")!

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: supabaseURL, supabasePublishableKey: nil)
        XCTAssertFalse(model.accountFeaturesEnabled)
        XCTAssertNotNil(model.accountUnavailableMessage)

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: nil, supabasePublishableKey: "sb_publishable_test")
        XCTAssertFalse(model.accountFeaturesEnabled)

        model.config = AppConfig(environment: .production, apiBaseURL: apiURL, supabaseURL: supabaseURL, supabasePublishableKey: "sb_publishable_test")
        XCTAssertTrue(model.accountFeaturesEnabled)
        XCTAssertNil(model.accountUnavailableMessage)
    }

    @MainActor
    func testRuntimeConfigReadsPublicArchiveInfoAndRejectsUnresolvedOrSecretValues() {
        let valid = AppConfig.fromProcessEnvironment(
            [:],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "https://project.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            ]
        )
        XCTAssertEqual(valid.supabaseURL, URL(string: "https://project.supabase.co"))
        XCTAssertEqual(valid.supabasePublishableKey, "sb_publishable_test")
        XCTAssertTrue(valid.hasUsableSupabaseAuthConfiguration)

        let unresolved = AppConfig.fromProcessEnvironment(
            [:],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "$(BRASSTUNE_SUPABASE_URL)",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "$(BRASSTUNE_SUPABASE_PUBLISHABLE_KEY)",
            ]
        )
        XCTAssertNil(unresolved.supabaseURL)
        XCTAssertNil(unresolved.supabasePublishableKey)
        XCTAssertFalse(unresolved.hasUsableSupabaseAuthConfiguration)

        let secretLike = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_secret_forbidden"
        )
        XCTAssertFalse(secretLike.hasUsableSupabaseAuthConfiguration)

        let environmentOverride = AppConfig.fromProcessEnvironment(
            [
                "BRASSTUNE_SUPABASE_URL": "https://override.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_override",
            ],
            bundleInfo: [
                "BRASSTUNE_SUPABASE_URL": "https://bundle.supabase.co",
                "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_bundle",
            ]
        )
        XCTAssertEqual(environmentOverride.supabaseURL, URL(string: "https://override.supabase.co"))
        XCTAssertEqual(environmentOverride.supabasePublishableKey, "sb_publishable_override")
    }

    func testProductionConfigurationRequiresExactImmutableOriginsAndJointAccountReadiness() {
        let supabase = URL(string: "https://project.supabase.co")!
        let key = "sb_publishable_test"
        let approved = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: supabase,
            supabasePublishableKey: key
        )
        XCTAssertTrue(approved.hasUsableAPIConfiguration)
        XCTAssertTrue(approved.hasUsableAccountConfiguration)

        for rejected in [
            "http://brasstune-u8qj.onrender.com",
            "https://localhost",
            "https://user:password@brasstune-u8qj.onrender.com",
            "https://api.example.test",
            "https://brasstune-u8qj.onrender.com?redirect=evil",
            "https://brasstune-u8qj.onrender.com.evil.test",
        ] {
            var config = approved
            config.apiBaseURL = URL(string: rejected)!
            XCTAssertFalse(config.hasUsableAPIConfiguration, rejected)
            XCTAssertFalse(config.hasUsableAccountConfiguration, rejected)
        }

        var missingAPI = approved
        missingAPI.apiBaseURL = URL(string: "https://api.example.test")!
        XCTAssertTrue(missingAPI.hasUsableSupabaseAuthConfiguration)
        XCTAssertFalse(missingAPI.hasUsableAccountConfiguration)

        var missingSupabase = approved
        missingSupabase.supabaseURL = nil
        XCTAssertTrue(missingSupabase.hasUsableAPIConfiguration)
        XCTAssertFalse(missingSupabase.hasUsableAccountConfiguration)
    }

    func testStringCatalogsCoverProductionLocalesPluralInterpolationMicCopyAndRTLHook() throws {
        let expectedLocales = Set(["ar", "de", "en", "es", "fr", "ja", "ko", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"])
        XCTAssertEqual(Set(AppLanguage.allCases.dropFirst().map(\.rawValue)), expectedLocales)
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertFalse(AppLanguage.english.isRightToLeft)

        let resourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BrassTuneApp/Resources", isDirectory: true)
        let localizableData = try Data(contentsOf: resourceDirectory.appendingPathComponent("Localizable.xcstrings"))
        let localizable = try XCTUnwrap(JSONSerialization.jsonObject(with: localizableData) as? [String: Any])
        let strings = try XCTUnwrap(localizable["strings"] as? [String: Any])
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(Set(localizations.keys), expectedLocales, "Missing production locale in \(key)")
        }
        let appSourceDirectory = resourceDirectory.deletingLastPathComponent()
        let sourceEnumerator = FileManager.default.enumerator(at: appSourceDirectory, includingPropertiesForKeys: nil)
        let expression = try NSRegularExpression(pattern: #"String\(localized: \"([^\"]+)\""#)
        while let sourceURL = sourceEnumerator?.nextObject() as? URL {
            guard sourceURL.pathExtension == "swift", let source = try? String(contentsOf: sourceURL, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let rawKey = String(source[keyRange])
                let key = rawKey.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
                XCTAssertNotNil(strings[key], "String(localized:) key missing from catalog: \(key)")
            }
        }
        let systemDefault = try XCTUnwrap(strings["System Default"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(systemDefault["localizations"] as? [String: Any]).keys), expectedLocales)
        let plural = try XCTUnwrap(strings["%lld practice sessions"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(plural["localizations"] as? [String: Any]).keys), expectedLocales)
        XCTAssertEqual(AppLanguage.english.practiceSessionCountLabel(1), "1 practice session")
        XCTAssertEqual(AppLanguage.english.practiceSessionCountLabel(2), "2 practice sessions")

        let infoData = try Data(contentsOf: resourceDirectory.appendingPathComponent("InfoPlist.xcstrings"))
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: infoData) as? [String: Any])
        let infoStrings = try XCTUnwrap(info["strings"] as? [String: Any])
        let mic = try XCTUnwrap(infoStrings["NSMicrophoneUsageDescription"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(mic["localizations"] as? [String: Any]).keys), expectedLocales)
    }

    func testKeychainSessionUsesThisDeviceOnlyAccessibility() {
        XCTAssertEqual(KeychainStore.sessionAccessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @MainActor
    func testLegacyAuthPayloadWithoutStableUserIDIsDeletedFailClosed() {
        let store = InMemoryAuthSessionStore()
        store.payload = #"{"accessToken":"legacy-token","refreshToken":"legacy-refresh","email":"legacy@example.com"}"#
        let service = AuthService(
            session: makeStubSession(),
            readSessionPayload: { store.payload },
            saveSessionPayload: { store.payload = $0 },
            deleteSessionPayload: { store.payload = nil }
        )

        XCTAssertNil(service.restoreSession())
        XCTAssertNil(store.payload)
    }

    @MainActor
    func testTutorialCompletionPersistsAndExplicitGuestEntryRequestsReplay() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store)

        XCTAssertFalse(model.tutorialCompleted)
        model.completeTutorial()

        let restored = AppModel(persistenceStore: store)
        XCTAssertTrue(restored.tutorialCompleted)
        XCTAssertEqual(restored.tutorialPresentationRequest, 0)

        restored.enterGuestDemo()
        XCTAssertEqual(restored.authState, .guest)
        XCTAssertEqual(restored.tutorialPresentationRequest, 1)
        XCTAssertTrue(restored.tutorialCompleted, "Replaying the tutorial must not erase prior completion.")
    }

    @MainActor
    func testPasswordResetClearsStaleErrorShowsSuccessAndGuardsDuplicateSubmission() async throws {
        let session = makeStubSession()
        let authService = AuthService(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
        model.lastError = .authenticationFailed
        nonisolated(unsafe) var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data("{}".utf8),
                delayNanoseconds: 150_000_000
            )
        }

        async let first: Void = model.requestPasswordReset(email: "player@example.com")
        try await Task.sleep(nanoseconds: 20_000_000)
        async let duplicate: Void = model.requestPasswordReset(email: "player@example.com")
        _ = await (first, duplicate)

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(model.authOperationInProgress)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.authNotice, "Password reset email sent. Check your inbox.")
        XCTAssertFalse(model.authNoticeIsError)
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testNewAccountAwaitingConfirmationRequestsTutorial() async {
        let session = makeStubSession()
        let authService = AuthService(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"user":{"email":"new@example.com"}}"#.utf8)
            )
        }

        await model.signUp(email: "new@example.com", password: "long-enough-password")

        XCTAssertEqual(model.authState, .emailConfirmationRequired(email: "new@example.com"))
        XCTAssertEqual(model.tutorialPresentationRequest, 1)
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.authNotice, "Account created. Check your email to confirm it, then use this tour to get started.")
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testSignedInRemoteDeletionWithoutUsableTokenFailsClosed() async {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let localSession = makeSession(name: "Keep me", cents: [-2, 0, 3])
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = makeAuthConfig()
        model.authState = .signedIn(email: "player@example.com")
        model.sessions = [localSession]
        nonisolated(unsafe) var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"deleted":true}"#.utf8)
            )
        }

        await model.deleteAccount()

        XCTAssertEqual(requestCount, 0, "Deletion must not reach the backend without a usable account token.")
        XCTAssertEqual(model.authState, .signedIn(email: "player@example.com"))
        XCTAssertEqual(model.sessions, [localSession])
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(statusCode: 401, message: "Your sign-in expired. Sign in again before deleting your account.")
        )
        XCTAssertEqual(model.authNotice, "Your sign-in expired. Sign in again before deleting your account.")
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testSignOutRevokesSupabaseSessionAndAlwaysClearsLocalCredential() async throws {
        for shouldFailOffline in [false, true] {
            let authService = makeIsolatedAuthService(session: makeStubSession())
            let config = makeAuthConfig()
            defer {
                authService.signOut()
                StubURLProtocol.handler = nil
            }
            nonisolated(unsafe) var logoutRequest: URLRequest?
            StubURLProtocol.handler = { request in
                if request.url?.path == "/auth/v1/logout" {
                    logoutRequest = request
                    if shouldFailOffline { throw URLError(.notConnectedToInternet) }
                    return .init(
                        response: HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                        data: Data()
                    )
                }
                return .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(#"{"access_token":"access-a","refresh_token":"refresh-a","expires_in":3600,"user":{"id":"user-a","email":"a@example.com"}}"#.utf8)
                )
            }
            _ = try await authService.signIn(email: "a@example.com", password: "password", config: config)
            XCTAssertNotNil(authService.restoreSession())

            if shouldFailOffline {
                do {
                    try await authService.signOut(config: config)
                    XCTFail("Expected offline logout to report a recoverable error")
                } catch {
                    XCTAssertEqual(error as? UserVisibleError, .networkUnavailable)
                }
            } else {
                try await authService.signOut(config: config)
            }

            XCTAssertNil(authService.restoreSession(), "Local credentials must clear even when server revocation is offline.")
            let request = try XCTUnwrap(logoutRequest)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-a")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        }
    }

    @MainActor
    func testAccountNamespacesPreventGuestOrCrossUserInheritanceAndDeletionSurvivesRelaunch() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-namespace-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-namespace-scores-\(UUID().uuidString)", isDirectory: true)
        let authService = makeIsolatedAuthService(session: makeStubSession())
        let config = makeAuthConfig()
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: NativeStorageNamespace.account(userID: "user-a").stateFile(basedAt: stateURL))
            try? FileManager.default.removeItem(at: NativeStorageNamespace.account(userID: "user-b").stateFile(basedAt: stateURL))
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path == "/auth/v1/logout" {
                return .init(response: response, data: Data())
            }
            if request.url?.host == AppConfig.approvedProductionAPIOrigin.host {
                return .init(response: response, data: Data(#"{"deleted":true}"#.utf8))
            }
            let body = requestBodyData(request) ?? Data()
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: String]
            let email = payload?["email"] ?? "a@example.com"
            let userID = email.hasPrefix("b") ? "user-b" : "user-a"
            let data = try JSONSerialization.data(withJSONObject: [
                "access_token": "access-\(userID)",
                "refresh_token": "refresh-\(userID)",
                "expires_in": 3_600,
                "user": ["id": userID, "email": email],
            ])
            return .init(response: response, data: data)
        }

        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        model.config = config
        let guestSession = makeSession(name: "Guest only", cents: [0])
        model.sessions = [guestSession]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Guest score")

        await model.signIn(email: "a@example.com", password: "password")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty, "Account A must not inherit guest scores.")
        let accountASession = makeSession(name: "Account A only", cents: [1])
        model.sessions = [accountASession]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Account A score")

        await model.signOut()
        XCTAssertEqual(model.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Guest score"])

        await model.signIn(email: "b@example.com", password: "password")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertTrue(model.scores.isEmpty, "Account B must not inherit account A or guest scores.")
        model.sessions = [makeSession(name: "Account B only", cents: [2])]

        await model.signOut()
        await model.signIn(email: "a@example.com", password: "password")
        XCTAssertEqual(model.sessions.map(\.id), [accountASession.id])
        XCTAssertEqual(model.scores.map(\.title), ["Account A score"])

        let relaunched = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        relaunched.config = config
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.sessions.map(\.id), [accountASession.id])
        XCTAssertEqual(relaunched.scores.map(\.title), ["Account A score"])

        let accountAFile = NativeStorageNamespace.account(userID: "user-a").stateFile(basedAt: stateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: accountAFile.path))
        await relaunched.deleteAccount()
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountAFile.path))
        XCTAssertEqual(relaunched.sessions.map(\.id), [guestSession.id])
        XCTAssertEqual(relaunched.scores.map(\.title), ["Guest score"])

        let afterDeletionRelaunch = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            apiClient: APIClient(session: makeStubSession()),
            authService: authService
        )
        afterDeletionRelaunch.config = config
        XCTAssertEqual(afterDeletionRelaunch.sessions.map(\.id), [guestSession.id])
        await afterDeletionRelaunch.signIn(email: "a@example.com", password: "password")
        XCTAssertTrue(afterDeletionRelaunch.sessions.isEmpty, "A deleted account namespace must stay deleted after relaunch.")
        XCTAssertTrue(afterDeletionRelaunch.scores.isEmpty)
    }

    @MainActor
    func testTerminalRefreshFailureClearsExpiredStoredSessionAndSignsOut() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-60,"user":{"id":"player-a","email":"player@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "player@example.com", password: "password", config: config)

        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"message":"refresh token is no longer valid"}"#.utf8)
            )
        }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(authService.restoreSession())
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(statusCode: 401, message: "Your sign-in expired. Sign in again, then retry.")
        )
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testCachedRemoteSessionIsRejectedAndClearedBeforeUseWhenRuntimeConfigIsInvalid() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
        }
        let validConfig = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"cached-token","refresh_token":"refresh-token","expires_in":3600,"user":{"id":"cached-user","email":"cached@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "cached@example.com", password: "password", config: validConfig)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = .local

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .missingAuthConfiguration)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testRetryableRefreshResponsesPreserveStoredSessionButKeepUIFailClosed() async throws {
        for statusCode in [429, 503] {
            let networkSession = makeStubSession()
            let authService = makeIsolatedAuthService(session: networkSession)
            let config = makeAuthConfig()
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-60,"user":{"id":"retry-user","email":"retry@example.com"}}"#.utf8)
                )
            }
            _ = try await authService.signIn(email: "retry@example.com", password: "password", config: config)
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
                    data: Data()
                )
            }
            let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
            model.config = config

            await model.restoreSession()

            XCTAssertEqual(model.authState, .signedOut)
            XCTAssertNotNil(authService.restoreSession(), "Retryable \(statusCode) failures must remain resumable.")
            XCTAssertEqual(
                model.lastError,
                .apiRequestFailed(
                    statusCode: statusCode,
                    message: "The account service couldn't refresh your sign-in right now. Your saved session will be retried later."
                )
            )
            XCTAssertTrue(model.authNoticeIsError)
            authService.signOut()
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testOfflineRefreshFallbackRequiresProvablyUnexpiredAccessToken() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"still-live-token","refresh_token":"refresh-token","expires_in":30,"user":{"id":"offline-user","email":"offline@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "offline@example.com", password: "password", config: config)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedIn(email: "offline@example.com"))
        XCTAssertNotNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .networkUnavailable)
        XCTAssertEqual(
            model.authNotice,
            "You're offline. BrassTune kept your unexpired sign-in for local practice; online account features may be unavailable."
        )
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testExpiredOfflineRefreshPreservesRetryableSessionButStaysSignedOut() async throws {
        let networkSession = makeStubSession()
        let authService = makeIsolatedAuthService(session: networkSession)
        defer {
            authService.signOut()
            StubURLProtocol.handler = nil
        }
        let config = makeAuthConfig()
        StubURLProtocol.handler = { request in
            .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: Data(#"{"access_token":"expired-token","refresh_token":"refresh-token","expires_in":-30,"user":{"id":"offline-user","email":"offline@example.com"}}"#.utf8)
            )
        }
        _ = try await authService.signIn(email: "offline@example.com", password: "password", config: config)
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
        model.config = config

        await model.restoreSession()

        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNotNil(authService.restoreSession())
        XCTAssertEqual(model.lastError, .networkUnavailable)
        XCTAssertTrue(model.authNoticeIsError)
    }

    @MainActor
    func testAppleIdentityAgeControlsTutorialWithoutInterruptingKnownReturningUsers() async {
        let timestamps: [(created: String?, last: String?, expectedRequest: Int, expectedNotice: String)] = [
            (
                "2026-07-16T19:00:00.000Z",
                "2026-07-16T19:00:00.000Z",
                1,
                "Apple account created. Here's a quick tour of BrassTune."
            ),
            (
                "2026-06-01T19:00:00.000Z",
                "2026-07-16T19:00:00.000Z",
                0,
                "Signed in with Apple."
            ),
            (
                nil,
                nil,
                1,
                "Signed in with Apple. Here's a quick tour you can finish or dismiss."
            ),
        ]

        for expectation in timestamps {
            let networkSession = makeStubSession()
            let authService = makeIsolatedAuthService(session: networkSession)
            let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
            let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), authService: authService)
            model.config = makeAuthConfig()
            var user: [String: String] = ["id": "apple-user", "email": "apple@example.com"]
            user["created_at"] = expectation.created
            user["last_sign_in_at"] = expectation.last
            let payload: [String: Any] = [
                "access_token": "apple-access-token",
                "refresh_token": "apple-refresh-token",
                "expires_in": 3_600,
                "user": user,
            ]
            StubURLProtocol.handler = { request in
                .init(
                    response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    data: try JSONSerialization.data(withJSONObject: payload)
                )
            }

            await model.completeAppleSignIn(identityToken: Data("apple-id-token".utf8), rawNonce: "nonce")

            XCTAssertEqual(model.authState, .signedIn(email: "apple@example.com"))
            XCTAssertEqual(model.tutorialPresentationRequest, expectation.expectedRequest)
            XCTAssertEqual(model.authNotice, expectation.expectedNotice)
            XCTAssertNil(model.lastError)
            authService.signOut()
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testMetronomeUserSettingsRemainAudibleAndPersistable() {
        let model = makeModel()

        XCTAssertFalse(model.metronomeTemporarilyMutedForRecording)
        model.setTempo(100)
        model.setMetronomeVolume(0.72)

        XCTAssertEqual(model.metronome.bpm, 100)
        XCTAssertFalse(model.metronome.muted)
        XCTAssertFalse(model.metronome.visualOnly)
        XCTAssertEqual(model.metronome.volume, 0.72, accuracy: 0.001)
    }

    @MainActor
    func testTapTempoClampsAndUpdatesBPM() {
        let model = makeModel()
        let start = Date(timeIntervalSince1970: 10)

        model.tapTempo(now: start)
        model.tapTempo(now: start.addingTimeInterval(0.5))
        model.tapTempo(now: start.addingTimeInterval(1.0))

        XCTAssertEqual(model.metronome.bpm, 120)
        model.setTempo(10)
        XCTAssertEqual(model.metronome.bpm, 30)
        model.setTempo(260)
        XCTAssertEqual(model.metronome.bpm, 240)
    }

    @MainActor
    func testScoreAnnotationAttachAndDelete() throws {
        let model = makeModel()
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let score = try XCTUnwrap(model.scores.first)
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]

        model.updateScoreAnnotation(
            scoreID: score.id,
            focusMeasures: "9-16",
            notes: "Tune releases",
            tempoTarget: 104,
            problemPassage: "second phrase"
        )
        model.attachScoreToLatestSession(scoreID: score.id)

        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.scores[0].annotation.focusMeasures, "9-16")
        XCTAssertEqual(model.sessions[0].attachedScoreID, score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions[0].attachedScoreID)
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("Local score"))
        XCTAssertFalse(model.sessions[0].practiceNotes.contains("9-16"))
    }

    @MainActor
    func testScoreDeleteFailureKeepsFileRecordAndSessionReference() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Protected score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        model.attachScoreToLatestSession(scoreID: score.id)

        model.deleteScore(id: score.id)

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.activeScoreID, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove the local score file, so the score was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        XCTAssertEqual(restored.scores.first?.id, score.id, "Failed file removal must roll the persisted deletion back.")
        XCTAssertEqual(restored.sessions.first?.attachedScoreID, score.id)
    }

    @MainActor
    func testScoreDeletePersistsCompletePostDeleteStateAcrossRelaunch() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Disposable score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        model.attachScoreToLatestSession(scoreID: score.id)

        model.deleteScore(id: score.id)

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertNil(model.sessions.first?.attachedScoreID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        XCTAssertTrue(restored.scores.isEmpty)
        XCTAssertNil(restored.sessions.first?.attachedScoreID)
    }

    @MainActor
    func testScoreDeleteSaveFailureKeepsPreDeleteStateAcrossRelaunch() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let durableStore = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let seedModel = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        try seedModel.importPhotoScore(data: makeTinyPNGData(), preferredName: "Durable score")
        let score = try XCTUnwrap(seedModel.scores.first)
        seedModel.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        seedModel.attachScoreToLatestSession(scoreID: score.id)

        let failingStore = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { _, _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        let model = AppModel(persistenceStore: failingStore, scoreStorageDirectory: scoreDirectory)
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.deleteScore(id: score.id)

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't save the score deletion, so the score and file were kept. Try again."
            )
        )
        let restored = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        XCTAssertEqual(restored.scores.first?.id, score.id)
        XCTAssertEqual(restored.sessions.first?.attachedScoreID, score.id)
    }

    @MainActor
    func testScoreDeleteRollbackFailureKeepsOpenModelAndReportsRecoveryRisk() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let durableStore = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let seedModel = AppModel(persistenceStore: durableStore, scoreStorageDirectory: scoreDirectory)
        try seedModel.importPhotoScore(data: makeTinyPNGData(), preferredName: "Rollback score")
        let score = try XCTUnwrap(seedModel.scores.first)
        seedModel.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        seedModel.attachScoreToLatestSession(scoreID: score.id)

        var writeCount = 0
        let transactionalStore = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            writeData: { data, url in
                writeCount += 1
                if writeCount == 2 {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let model = AppModel(
            persistenceStore: transactionalStore,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.deleteScore(id: score.id)

        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.first?.attachedScoreID, score.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove the local score file or restore its saved state. The score is still open; export your data before closing the app."
            )
        )
    }

    @MainActor
    func testClearingLocalPracticeDataRemovesImportedScoreFiles() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Local score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        model.clearLocalPracticeData()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testFailedPhotoImportRemovesCopiedScoreFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        XCTAssertThrowsError(try model.importPhotoScore(data: Data("not an image".utf8), preferredName: "Broken score"))

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(storedFiles.isEmpty)
    }

    @MainActor
    func testPDFOverPageLimitIsRejectedWithoutLeavingCopiedFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneOversized-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        let pdfData = makePDFData(pageCount: 33)
        try pdfData.write(to: sourceURL, options: [.atomic])
        XCTAssertEqual(PDFDocument(data: pdfData)?.pageCount, 33, "Regression fixture must be a real 33-page PDF.")
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        XCTAssertThrowsError(try model.importScore(from: sourceURL)) { error in
            XCTAssertEqual(error as? NativeScoreImportService.ImportError, .tooManyPages(maximum: 32))
        }

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(storedFiles.isEmpty, "Rejected PDFs must be removed from imported-score storage.")
    }

    @MainActor
    func testPDFOverPageLimitReportsCleanupFailureWhenCopiedFileCannotBeRemoved() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneOversized-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
            try? FileManager.default.removeItem(at: sourceURL)
        }
        try makePDFData(pageCount: 33).write(to: sourceURL, options: [.atomic])
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )

        XCTAssertThrowsError(try model.importScore(from: sourceURL)) { error in
            XCTAssertEqual(error as? NativeScoreImportService.ImportError, .cleanupFailed)
            XCTAssertTrue(error.localizedDescription.contains("copied file remains"))
        }

        XCTAssertTrue(model.scores.isEmpty)
        let storedFiles = (try? FileManager.default.contentsOfDirectory(at: scoreDirectory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(storedFiles.count, 1, "The failed removal is surfaced instead of being reported as successful cleanup.")
    }

    @MainActor
    func testClearLocalPracticeDataFailureKeepsModelAndFile() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(
            persistenceStore: store,
            scoreStorageDirectory: scoreDirectory,
            scoreFileRemover: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        model.sessions = [makeSession(name: "Recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Protected score")
        let storedURL = try XCTUnwrap(model.scores.first.flatMap { model.storedScoreFileURL(for: $0) })

        model.clearLocalPracticeData()

        XCTAssertEqual(model.scores.count, 1)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't remove your imported score files, so your local practice data was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        XCTAssertEqual(restored.scores.count, 1, "A score-cleanup failure must restore the snapshot cleared earlier in the transaction.")
        XCTAssertEqual(restored.sessions.count, 1)
    }

    @MainActor
    func testPersistenceClearFailureKeepsModelFilesAndRestorableSnapshot() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: stateURL)
            try? FileManager.default.removeItem(at: scoreDirectory)
        }
        let store = NativePersistenceStore.ephemeral(
            fileURL: stateURL,
            removeItem: { _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        )
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        model.sessions = [makeSession(name: "Persistent recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Persistent score")
        let score = try XCTUnwrap(model.scores.first)
        let storedURL = try XCTUnwrap(model.storedScoreFileURL(for: score))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))

        model.clearLocalPracticeData()

        XCTAssertEqual(model.scores.first?.id, score.id)
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(
            model.lastError,
            .apiRequestFailed(
                statusCode: 500,
                message: "BrassTune couldn't clear its saved local data, so your practice data was kept. Try again."
            )
        )

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)
        XCTAssertEqual(restored.scores.first?.id, score.id, "Failed clear must not claim success before stale state can reappear on launch.")
        XCTAssertEqual(restored.sessions.count, 1)
    }

    @MainActor
    func testAccountDeletionRemovesImportedScoreFiles() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)

        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Disposable score")
        let fileName = try XCTUnwrap(model.scores.first?.localFileName)
        let storedURL = scoreDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        await model.deleteAccount()

        XCTAssertTrue(model.scores.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoreDirectory.path))
    }

    @MainActor
    func testLocalPersistenceRestoresLiveSessionsSettingsScoresAndMetronome() throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let model = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        model.selectedInstrumentId = "horn"
        model.referencePitchHz = 442.0
        model.setTempo(108)
        model.setMetronomeVolume(0.7)
        model.sessions = [makeSession(name: "Saved recording", cents: [-2, 0, 3])]
        try model.importPhotoScore(data: makeTinyPNGData(), preferredName: "Saved score")

        let restored = AppModel(persistenceStore: store, scoreStorageDirectory: scoreDirectory)

        XCTAssertEqual(restored.selectedInstrumentId, "horn")
        XCTAssertEqual(restored.referencePitchHz, 442.0)
        XCTAssertEqual(restored.metronome.bpm, 108)
        XCTAssertEqual(restored.metronome.volume, 0.7, accuracy: 0.001)
        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.sessions.first?.source, .live)
        XCTAssertEqual(restored.scores.count, 1)
        XCTAssertEqual(restored.scores.first?.sourceKind, .photos)
        XCTAssertEqual(restored.activeScoreID, restored.scores.first?.id)
    }

    @MainActor
    func testLegacySilentMetronomeDefaultsMigrateToAudibleDefaults() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        var legacyMetronome = MetronomeSettings()
        legacyMetronome.muted = true
        legacyMetronome.visualOnly = true
        legacyMetronome.volume = 0
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [],
                scores: [],
                activeScoreID: nil,
                metronome: legacyMetronome,
                metronomeDefaultsVersion: 1
            )
        )

        let restored = AppModel(persistenceStore: store)

        XCTAssertFalse(restored.metronome.muted)
        XCTAssertFalse(restored.metronome.visualOnly)
        XCTAssertEqual(restored.metronome.volume, 0.6, accuracy: 0.001)
    }

    @MainActor
    func testShippingRestoreQuarantinesLegacyFixtureSessionsAndScores() {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let store = NativePersistenceStore.ephemeral(fileURL: stateURL)
        let sampleSession = makeSession(name: "Old test recording", cents: [0], source: .sample)
        let sampleScore = makeSampleScore()
        store.save(
            NativeLocalSnapshot(
                selectedInstrumentId: "trumpet",
                referencePitchHz: 440,
                sessions: [sampleSession],
                scores: [sampleScore],
                activeScoreID: sampleScore.id,
                metronome: MetronomeSettings(),
                metronomeDefaultsVersion: 2
            )
        )

        let restored = AppModel(persistenceStore: store)

        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertTrue(restored.scores.isEmpty)
        XCTAssertNil(restored.activeScoreID)
    }

    // MARK: - Play-Along web parity

    func testPlayAlongUsesTwoSecondDefaultAndDoesNotAdvanceEarly() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"])

        XCTAssertEqual(grader.holdDurationMs, 2_000)
        for timestamp in stride(from: 0, through: 1_750, by: 250) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: timestamp))
        }
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 1_999))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 1_999.0 / 2_000.0, accuracy: 0.000_1)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 2_000))
        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongRatingUsesWebCentsThresholds() {
        XCTAssertEqual(PlayAlongNoteRating(cents: 5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: -5), .excellent)
        XCTAssertEqual(PlayAlongNoteRating(cents: 15), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: -15), .close)
        XCTAssertEqual(PlayAlongNoteRating(cents: 15.1), .off)
        XCTAssertEqual(PlayAlongNoteRating(cents: -30), .off)
        XCTAssertEqual(PlayAlongNoteRating(cents: nil), .missed)
        XCTAssertEqual(PlayAlongNoteRating(cents: .nan), .missed)
    }

    func testSharedPlayAlongContractFixtureMatchesNativeScorer() throws {
        let data = try Data(contentsOf: try sharedFixtureURL(named: "play_along_contract.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let policy = try XCTUnwrap(root["policy"] as? [String: Any])
        let grader = PlayAlongGrader(writtenNotes: ["C"])
        XCTAssertEqual(grader.holdDurationMs, policy["hold_ms"] as? Int)
        XCTAssertEqual(grader.minimumConfidence, policy["minimum_confidence"] as? Double)
        XCTAssertEqual(grader.minimumSamples, policy["minimum_samples"] as? Int)
        XCTAssertEqual(grader.attackTrimMs, policy["attack_trim_ms"] as? Int)
        XCTAssertEqual(grader.maximumDropoutMs, policy["maximum_dropout_ms"] as? Int)

        for item in try XCTUnwrap(root["rating_cases"] as? [[String: Any]]) {
            let cents = item["cents"] is NSNull ? nil : item["cents"] as? Double
            let rating = PlayAlongNoteRating(cents: cents)
            XCTAssertEqual(rating.rawValue, item["expected_rating"] as? String, item["name"] as? String ?? "rating")
            XCTAssertEqual(rating.isCentered, item["expected_centered"] as? Bool)
            XCTAssertEqual(rating.isAccepted, item["expected_accepted"] as? Bool)
        }

        for item in try XCTUnwrap(root["star_cases"] as? [[String: Any]]) {
            let percent = item["in_tune_percent"] is NSNull ? nil : item["in_tune_percent"] as? Double
            XCTAssertEqual(PlayAlongGrade.starRating(inTunePercentage: percent), item["expected_stars"] as? Int)
        }

        for item in try XCTUnwrap(root["summary_cases"] as? [[String: Any]]) {
            let ratings = try XCTUnwrap(item["ratings"] as? [[String: Any]])
            let grades = ratings.enumerated().map { index, rating -> PlayAlongNoteGrade in
                let cents = rating["cents"] is NSNull ? nil : rating["cents"] as? Double
                let expectedRating = PlayAlongNoteRating(rawValue: rating["rating"] as? String ?? "")
                return PlayAlongNoteGrade(
                    writtenNoteName: "N\(index)",
                    medianCents: cents,
                    sampleCount: cents == nil ? 0 : 5,
                    rating: expectedRating
                )
            }
            let summary = PlayAlongGrade(expectedNoteCount: item["expected_total"] as? Int ?? 0, noteGrades: grades)
            XCTAssertEqual(summary.totalNotes, item["expected_total"] as? Int)
            XCTAssertEqual(summary.notesPlayed, item["expected_hit"] as? Int)
            XCTAssertEqual(summary.inTuneNotes, item["expected_in_tune"] as? Int)
            XCTAssertEqual(summary.inTunePercentage, item["expected_in_tune_percent"] as? Int)
            XCTAssertEqual(summary.averageAbsoluteCents, item["expected_average_abs_cents"] as? Double)
            XCTAssertEqual(summary.stars, item["expected_stars"] as? Int)
        }
    }

    func testSharedReferenceToneDroneAndTranspositionFixturesMatchNativeMath() throws {
        let referenceData = try Data(contentsOf: try sharedFixtureURL(named: "reference_tone_cases.json"))
        let referenceCases = try XCTUnwrap(JSONSerialization.jsonObject(with: referenceData) as? [[String: Any]])
        for item in referenceCases {
            let midi = try writtenMIDI(from: try XCTUnwrap(item["written_note"] as? String))
            let semitones = try XCTUnwrap(item["interval_semitones"] as? Int)
            let interval = try XCTUnwrap(TuningInterval(rawValue: semitones))
            let frequency = try XCTUnwrap(PracticePitchMath.frequency(
                writtenMIDI: midi,
                interval: interval,
                instrumentID: try XCTUnwrap(item["instrument_id"] as? String),
                referencePitchHz: try XCTUnwrap(item["reference_pitch_hz"] as? Double)
            ))
            XCTAssertEqual(frequency, try XCTUnwrap(item["expected_frequency_hz"] as? Double), accuracy: 0.000_1)
        }

        let droneData = try Data(contentsOf: try sharedFixtureURL(named: "drone_dyad_cases.json"))
        let droneCases = try XCTUnwrap(JSONSerialization.jsonObject(with: droneData) as? [[String: Any]])
        for item in droneCases {
            let frequencies = try XCTUnwrap(PracticePitchMath.frequencies(
                writtenMIDI: try writtenMIDI(from: try XCTUnwrap(item["written_note"] as? String)),
                interval: try XCTUnwrap(TuningInterval(rawValue: try XCTUnwrap(item["interval_semitones"] as? Int))),
                instrumentID: try XCTUnwrap(item["instrument_id"] as? String),
                referencePitchHz: try XCTUnwrap(item["reference_pitch_hz"] as? Double)
            ))
            let expected = try XCTUnwrap(item["expected_frequencies_hz"] as? [Double])
            XCTAssertEqual(frequencies.count, expected.count)
            for (actual, target) in zip(frequencies, expected) {
                XCTAssertEqual(actual, target, accuracy: 0.000_1)
            }
        }

        let transpositionData = try Data(contentsOf: try sharedFixtureURL(named: "transposition_cases.json"))
        let transpositionCases = try XCTUnwrap(JSONSerialization.jsonObject(with: transpositionData) as? [[String: Any]])
        for item in transpositionCases {
            let instrumentID = try XCTUnwrap(item["instrument_id"] as? String)
            let expectedWritten = try XCTUnwrap(item["expected_written_midi"] as? Int)
            XCTAssertEqual(
                PracticePitchMath.concertMIDI(forWrittenMIDI: expectedWritten, instrumentID: instrumentID),
                item["concert_midi"] as? Int
            )
        }
    }

    func testPlayAlongExerciseCatalogIncludesAllGroupedScalesAndPracticePatterns() {
        let major = PlayAlongExercise.library.filter { $0.category == .major }
        let minor = PlayAlongExercise.library.filter { $0.category == .naturalMinor }
        let patterns = PlayAlongExercise.library.filter { $0.category == .practicePattern }
        XCTAssertEqual(PlayAlongExercise.defaultExercise.id, "cmaj")
        XCTAssertEqual(major.count, 12)
        XCTAssertEqual(minor.count, 12)
        XCTAssertEqual(patterns.count, 3)
        XCTAssertEqual(PlayAlongExercise.library.count, 27)
        XCTAssertEqual(Set(PlayAlongExercise.library.map(\.id)).count, PlayAlongExercise.library.count)
        XCTAssertTrue(["cmaj", "fmaj", "gmaj", "arpeggio", "chromatic", "longtones"].allSatisfy { id in
            PlayAlongExercise.library.contains { $0.id == id }
        })
        XCTAssertFalse(PlayAlongExercise.library.contains { $0.writtenNotes.isEmpty })
    }

    func testPlayAlongScaleIntervalsMatchMajorAndNaturalMinorPatterns() throws {
        let expected: [PlayAlongExerciseCategory: [Int]] = [
            .major: [0, 2, 4, 5, 7, 9, 11, 0],
            .naturalMinor: [0, 2, 3, 5, 7, 8, 10, 0],
        ]
        for exercise in PlayAlongExercise.library where exercise.category != .practicePattern {
            let tonic = try XCTUnwrap(testPitchClass(exercise.writtenNotes[0]), exercise.title)
            let intervals = try exercise.writtenNotes.map { note in
                let pitchClass = try XCTUnwrap(testPitchClass(note), "Unsupported note spelling \(note) in \(exercise.title)")
                return (pitchClass - tonic + 12) % 12
            }
            XCTAssertEqual(intervals, expected[exercise.category], exercise.title)
            XCTAssertEqual(exercise.writtenNotes.first, exercise.writtenNotes.last, exercise.title)
        }
    }

    func testEnsembleSummaryUsesExplicitViewerCapabilitiesWithoutJoinCodeInference() throws {
        let decoder = JSONDecoder()
        let owner = try decoder.decode(
            EnsembleSummary.self,
            from: Data(#"{"id":1,"name":"Wind Ensemble","director_user_id":42,"join_code":null,"viewer_role":"owner","viewer_can_leave":false,"viewer_can_manage":true,"created_at":"2026-07-12T12:00:00.123456","updated_at":"2026-07-12T12:00:00.123456"}"#.utf8)
        )
        let member = try decoder.decode(
            EnsembleSummary.self,
            from: Data(#"{"id":2,"name":"Brass Choir","join_code":"VISIBLE-BUT-NOT-AUTHZ","viewer_role":"assistant","viewer_can_leave":true,"viewer_can_manage":false,"created_at":"2026-07-12T12:00:00","updated_at":"2026-07-12T12:00:00"}"#.utf8)
        )

        XCTAssertFalse(owner.canLeave)
        XCTAssertTrue(member.canLeave)
        XCTAssertEqual(owner.viewerRoleLabel, "Class owner")
        XCTAssertEqual(member.viewerRoleLabel, "Assistant")
    }

    func testAPIClientPreservesFastAPIValidationMessagesAndCancellation() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let baseURL = AppConfig.approvedProductionAPIOrigin
        let config = AppConfig(environment: .staging, apiBaseURL: baseURL, supabaseURL: nil, supabasePublishableKey: nil)

        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"detail":[{"loc":["body","code"],"msg":"Class code must contain 4-16 characters","type":"value_error"},{"loc":["body","instrument_id"],"msg":"Instrument is not supported","type":"value_error"}]}"#.utf8)
            return .init(response: response, data: data)
        }
        do {
            let _: TestAPIResponse = try await client.request(TestAPIResponse.self, path: "/api/ensemble/join", config: config)
            XCTFail("Expected validation failure")
        } catch let error as UserVisibleError {
            XCTAssertEqual(
                error,
                .apiRequestFailed(
                    statusCode: 422,
                    message: "Class code must contain 4-16 characters Instrument is not supported"
                )
            )
        }

        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        do {
            let _: TestAPIResponse = try await client.request(TestAPIResponse.self, path: "/api/ensemble/groups", config: config)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: view-lifecycle cancellation is not surfaced as a network error.
        }
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testClassJoinAndLeaveUseExpectedAPIContractAndBearer() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            apiClient: client,
            classAccessTokenProvider: { _ in "fresh-token" }
        )
        model.config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: nil,
            supabasePublishableKey: nil
        )
        nonisolated(unsafe) var capturedRequests: [CapturedRequest] = []
        StubURLProtocol.handler = { request in
            capturedRequests.append(
                CapturedRequest(
                    method: request.httpMethod ?? "GET",
                    path: request.url?.path ?? "",
                    authorization: request.value(forHTTPHeaderField: "Authorization"),
                    body: requestBodyData(request)
                )
            )
            let path = request.url!.path
            let data: Data
            if request.httpMethod == "POST" {
                data = Data(#"{"joined":true,"group_id":7,"group_name":"Jazz Band"}"#.utf8)
            } else if request.httpMethod == "DELETE" {
                data = Data(#"{"left":true,"group_id":7}"#.utf8)
            } else if path == "/api/ensemble/groups" {
                data = Data(#"[{"id":7,"name":"Jazz Band","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8)
            } else {
                data = Data()
            }
            return .init(
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data: data
            )
        }

        let joined = await model.joinEnsemble(code: " ab cd ")
        XCTAssertTrue(joined)
        XCTAssertEqual(model.ensembles.map(\.id), [7])
        let left = await model.leaveEnsemble(id: 7)
        XCTAssertTrue(left)
        XCTAssertTrue(model.ensembles.isEmpty)

        let post = try XCTUnwrap(capturedRequests.first { $0.method == "POST" })
        XCTAssertEqual(post.path, "/api/ensemble/join")
        XCTAssertEqual(post.authorization, "Bearer fresh-token")
        let body = try XCTUnwrap(post.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload["code"], "ABCD")
        XCTAssertEqual(payload["instrument_id"], "trumpet")
        let delete = try XCTUnwrap(capturedRequests.first { $0.method == "DELETE" })
        XCTAssertEqual(delete.path, "/api/ensemble/groups/7/membership")
        XCTAssertEqual(delete.authorization, "Bearer fresh-token")
        StubURLProtocol.handler = nil
    }

    @MainActor
    func testOlderClassLoadCannotOverwritePostJoinAuthoritativeRefresh() async throws {
        let session = makeStubSession()
        let client = APIClient(session: session)
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            apiClient: client,
            classAccessTokenProvider: { _ in "fresh-token" }
        )
        model.config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: nil,
            supabasePublishableKey: nil
        )
        nonisolated(unsafe) var getCount = 0
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "POST" {
                return .init(response: response, data: Data(#"{"joined":true,"group_id":2,"group_name":"New Class"}"#.utf8))
            }
            getCount += 1
            if getCount == 1 {
                return .init(
                    response: response,
                    data: Data(#"[{"id":1,"name":"Stale Class","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8),
                    delayNanoseconds: 250_000_000
                )
            }
            return .init(
                response: response,
                data: Data(#"[{"id":2,"name":"New Class","viewer_role":"student","viewer_can_leave":true,"viewer_can_manage":false}]"#.utf8)
            )
        }

        async let staleLoad: Void = model.loadEnsembles()
        try await Task.sleep(nanoseconds: 40_000_000)
        let joined = await model.joinEnsemble(code: "ABCD")
        XCTAssertTrue(joined)
        await staleLoad

        XCTAssertEqual(model.ensembles.map(\.id), [2])
        XCTAssertEqual(model.selectedEnsembleID, 2)
        StubURLProtocol.handler = nil
    }

    func testPlayAlongAdvancesAfterSustainedCorrectWrittenPitchClass() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 500, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 10, timestampMs: timestamp))
        }

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].writtenNoteName, "C")
        XCTAssertEqual(grader.noteGrades[0].medianCents ?? .nan, 10, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades[0].rating, .close)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongDoesNotAdvanceOnBriefTouch() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongWrongConfidentNoteResetsHold() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "E", cents: 5, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 300))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 400))

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
        XCTAssertEqual(grader.heldFraction, 0.25, accuracy: 0.001)
    }

    func testPlayAlongToleratesBriefLowConfidenceSilence() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: nil, cents: nil, timestampMs: 100, confidence: 0.1, frequencyHz: nil))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 440))
        grader.feed(makePlayAlongFrame(note: "C", cents: 8, timestampMs: 640))

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.rating, .close)
    }

    func testPlayAlongPausesVisibleProgressDuringBriefDropout() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3)

        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 100))
        let beforeDropout = grader.heldFraction
        grader.feed(makePlayAlongFrame(note: nil, cents: nil, timestampMs: 200, confidence: 0.1, frequencyHz: nil))
        let duringDropout = grader.heldFraction
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 250))

        XCTAssertEqual(beforeDropout, 0.25, accuracy: 0.001)
        XCTAssertEqual(duringDropout, beforeDropout, accuracy: 0.001)
        XCTAssertEqual(grader.heldFraction, beforeDropout, accuracy: 0.001)
        XCTAssertTrue(grader.noteGrades.isEmpty)
    }

    func testPlayAlongVoiceOverAnnouncementNamesNextNoteAndCompletion() {
        let exercise = PlayAlongExercise(
            id: "announcement-test",
            title: "Announcement test",
            detail: "Two notes",
            difficulty: "Test",
            category: .practicePattern,
            writtenNotes: ["C", "D"]
        )
        var session = PlayAlongSession(exercise: exercise, holdDurationMs: 100, minimumSamples: 2, attackTrimMs: 0)
        session.feed(makePlayAlongFrame(note: "C", cents: 0, timestampMs: 0))
        session.feed(makePlayAlongFrame(note: "C", cents: 0, timestampMs: 100))

        XCTAssertEqual(playAlongAdvanceAnnouncement(for: session), "Next note is D. Hold it steady for two seconds.")

        session.feed(makePlayAlongFrame(note: "D", cents: 0, timestampMs: 200))
        session.feed(makePlayAlongFrame(note: "D", cents: 0, timestampMs: 300))
        XCTAssertEqual(playAlongAdvanceAnnouncement(for: session), "Exercise complete. Your results are ready.")
    }

    func testInstrumentSetupHasAStableVoiceOverFocusAnnouncement() {
        XCTAssertEqual(nativeTutorialSteps.count, 1)
        let announcement = nativeTutorialAccessibilityAnnouncement(stepIndex: 0)
        XCTAssertTrue(announcement.contains("Step 1 of 1"))
        XCTAssertTrue(announcement.contains("Choose your instrument"))
    }

    func testPlayAlongLongSilenceResetsHoldAfterDropoutGrace() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            maximumDropoutMs: 250
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 100))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 500))

        XCTAssertEqual(grader.heldFraction, 0, accuracy: 0.001)

        for timestamp in stride(from: 600, through: 800, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }

        XCTAssertFalse(grader.isComplete)
        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongTrimsBrassAttackTransient() {
        var grader = PlayAlongGrader(
            writtenNotes: ["C"],
            holdDurationMs: 400,
            minimumSamples: 3,
            attackTrimMs: 120
        )

        grader.feed(makePlayAlongFrame(note: "C", cents: 45, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 30, timestampMs: 80))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 200))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 320))
        grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: 450))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 4, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongMedianRejectsSingleDetectorOutlier() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 400, minimumSamples: 3, attackTrimMs: 0)

        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 0))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 120))
        grader.feed(makePlayAlongFrame(note: "C", cents: 60, timestampMs: 240))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 360))
        grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: 480))

        XCTAssertEqual(grader.noteGrades.first?.medianCents ?? .nan, 5, accuracy: 0.001)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongIgnoresFramesBelowConfidenceGate() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 600, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 5, timestampMs: timestamp, confidence: 0.4))
        }

        XCTAssertTrue(grader.noteGrades.isEmpty)
        XCTAssertEqual(grader.currentNoteName, "C")
    }

    func testPlayAlongAcceptsIntermediateConfidenceWithoutRecordingValidity() {
        var grader = PlayAlongGrader(writtenNotes: ["C"], holdDurationMs: 300, minimumSamples: 3)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            let frame = makePlayAlongFrame(
                note: "C",
                cents: 3,
                timestampMs: timestamp,
                confidence: 0.7,
                isValidForRecording: false
            )
            XCTAssertFalse(frame.isValidForRecording)
            grader.feed(frame)
        }

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testPlayAlongSkipMarksMissedAndAdvances() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"])

        grader.skipCurrentNote()

        XCTAssertEqual(grader.noteGrades.count, 1)
        XCTAssertEqual(grader.noteGrades[0].rating, .missed)
        XCTAssertNil(grader.noteGrades[0].medianCents)
        XCTAssertEqual(grader.currentNoteName, "D")
    }

    func testPlayAlongCompletesAndSummarizesLikeWebGrader() {
        var grader = PlayAlongGrader(writtenNotes: ["C", "D"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "C", cents: 4, timestampMs: timestamp))
        }
        for timestamp in stride(from: 1_000, through: 1_400, by: 100) {
            grader.feed(makePlayAlongFrame(note: "D", cents: 12, timestampMs: timestamp))
        }

        XCTAssertTrue(grader.isComplete)
        let summary = PlayAlongGrade(expectedNoteCount: 2, noteGrades: grader.noteGrades)
        XCTAssertEqual(summary.totalNotes, 2)
        XCTAssertEqual(summary.notesPlayed, 2)
        XCTAssertEqual(summary.inTuneNotes, 1)
        XCTAssertEqual(summary.inTunePercentage, 50)
        XCTAssertEqual(summary.averageAbsoluteCents ?? .nan, 8, accuracy: 0.001)
        XCTAssertEqual(summary.stars, 0)
    }

    func testPlayAlongMatchesWrittenPitchClassAcrossEnharmonicSpellingAndOctave() {
        var grader = PlayAlongGrader(writtenNotes: ["Bb"], holdDurationMs: 300, minimumSamples: 3, attackTrimMs: 0)

        for timestamp in stride(from: 0, through: 300, by: 100) {
            grader.feed(makePlayAlongFrame(note: "A#", cents: 2, timestampMs: timestamp, writtenOctave: 6))
        }

        XCTAssertTrue(grader.isComplete)
        XCTAssertEqual(grader.noteGrades.first?.writtenNoteName, "Bb")
        XCTAssertEqual(grader.noteGrades.first?.rating, .excellent)
    }

    func testDetectedFramesApplyWrittenPitchTranspositionForTrumpetAndHorn() {
        let trumpet = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 233.081_880_8,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        let horn = PitchFrame.detected(
            timestampMs: 0,
            frequencyHz: 174.614_115_7,
            confidence: 0.99,
            rms: 0.08,
            instrumentId: "horn",
            referencePitchHz: 440
        )

        XCTAssertEqual(trumpet.writtenNoteName, "C")
        XCTAssertEqual(trumpet.writtenOctave, 4)
        XCTAssertEqual(horn.writtenNoteName, "C")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    // MARK: - Pitch detector and BrassTuneCore integration

    func testFixtureFramesReflectInstrumentTransposition() {
        let trumpet = PitchFrame.fixture(index: 0, instrumentId: "trumpet")
        let horn = PitchFrame.fixture(index: 0, instrumentId: "horn")

        XCTAssertEqual(trumpet.writtenNoteName, "D")
        XCTAssertEqual(trumpet.writtenOctave, 5)
        XCTAssertEqual(horn.writtenNoteName, "D")
        XCTAssertEqual(horn.writtenOctave, 4)
    }

    func testCoreTuningStatusIsAvailableToApp() {
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: 7, confidence: 0.98, rms: 0.1), .sharp)
        XCTAssertEqual(BrassTuneCore.tuningStatus(cents: nil, confidence: 0.99, rms: 0.1), .noLock)
    }

    func testNativePitchDetectorLocksSyntheticSineAndAppliesReferencePitch() {
        let sampleRate = 44_100.0
        let frequency = 442.0
        let samples = (0..<4096).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.2)
        }

        let frame = NativePitchDetector.frame(
            samples: samples,
            sampleRate: sampleRate,
            timestampMs: 120,
            instrumentId: "trumpet",
            referencePitchHz: 442.0
        )

        XCTAssertEqual(frame.tuningStatus, .inTune)
        XCTAssertEqual(frame.writtenNoteName, "B")
        XCTAssertEqual(frame.writtenOctave, 4)
        XCTAssertTrue(frame.isValidForRecording)
        XCTAssertEqual(frame.frequencyHz ?? 0, 442.0, accuracy: 3.0)
        XCTAssertGreaterThan(frame.confidence, 0.95)
    }

    func testNativePitchDetectorReportsSilenceAndNoLock() {
        let silent = NativePitchDetector.frame(
            samples: Array(repeating: Float(0), count: 4096),
            sampleRate: 44_100,
            timestampMs: 1,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(silent.tuningStatus, .silence)
        XCTAssertFalse(silent.isValidForRecording)

        var seed: UInt64 = 0xBADC0DE
        let noise = (0..<4096).map { _ -> Float in
            seed = seed &* 6364136223846793005 &+ 1
            let unit = Double((seed >> 33) & 0xFFFF) / 65_535.0
            return Float((unit * 2.0 - 1.0) * 0.025)
        }
        let noLock = NativePitchDetector.frame(
            samples: noise,
            sampleRate: 44_100,
            timestampMs: 2,
            instrumentId: "trumpet",
            referencePitchHz: 440
        )
        XCTAssertEqual(noLock.tuningStatus, .noLock)
        XCTAssertFalse(noLock.isValidForRecording)
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel() -> AppModel {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTune-\(UUID().uuidString).json")
        let scoreDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BrassTuneScores-\(UUID().uuidString)", isDirectory: true)
        return AppModel(persistenceStore: .ephemeral(fileURL: stateURL), scoreStorageDirectory: scoreDirectory)
    }

    @MainActor
    private func makeIsolatedAuthService(session: URLSession) -> AuthService {
        let store = InMemoryAuthSessionStore()
        return AuthService(
            session: session,
            service: "com.brasstune.tests.\(UUID().uuidString)",
            account: "current-session",
            readSessionPayload: { store.payload },
            saveSessionPayload: { store.payload = $0 },
            deleteSessionPayload: { store.payload = nil }
        )
    }

    private func makeAuthConfig() -> AppConfig {
        AppConfig(
            environment: .production,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: URL(string: "https://project.supabase.co")!,
            supabasePublishableKey: "sb_publishable_test"
        )
    }

    private func sharedFixtureURL(named name: String) throws -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["BRASSTUNE_SHARED_FIXTURES_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent("fixtures", isDirectory: true).appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else {
            throw XCTSkip("Shared audio fixture \(name) is not present in this isolated worktree.")
        }
        return url
    }

    private func writtenMIDI(from label: String) throws -> Int {
        let pattern = #"^([A-G])([#b]?)(-?\d+)$"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        let match = try XCTUnwrap(expression.firstMatch(in: label, range: range))
        let note = String(label[Range(match.range(at: 1), in: label)!])
            + String(label[Range(match.range(at: 2), in: label)!])
        let octave = try XCTUnwrap(Int(label[Range(match.range(at: 3), in: label)!]))
        let pitchClass = try XCTUnwrap([
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
            "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
        ][note])
        return (octave + 1) * 12 + pitchClass
    }

    private func makeSession(
        name: String,
        cents: [Double],
        source: PracticeSessionSource = .live
    ) -> PracticeSession {
        let frames = cents.enumerated().map { index, centsValue in
            PitchFrame(
                timestampMs: index * 110,
                frequencyHz: 440,
                confidence: 0.98,
                rms: 0.08,
                centsDeviation: centsValue,
                tuningStatus: BrassTuneCore.tuningStatus(cents: centsValue, confidence: 0.98, rms: 0.08),
                writtenNoteName: "A",
                writtenOctave: 4,
                isValidForRecording: true
            )
        }
        let startedAt = Date(timeIntervalSince1970: 1_000)
        return PracticeSession(
            id: UUID(),
            name: name,
            instrumentId: "trumpet",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(frames.count) * 0.11),
            frames: frames,
            retainedRecordingURL: nil,
            source: source
        )
    }

    private func makeSampleScore() -> ImportedScore {
        let page = ScorePage(
            id: UUID(),
            pageNumber: 1,
            titleSuggestion: nil,
            textSuggestions: [],
            thumbnailPNGData: nil
        )
        return ImportedScore(
            id: UUID(),
            title: "Old test score",
            composer: nil,
            sourceKind: .sample,
            localFileName: nil,
            importedAt: Date(timeIntervalSince1970: 1_000),
            pages: [page],
            selectedPageID: page.id
        )
    }

    private func makePlayAlongFrame(
        note: String?,
        cents: Double?,
        timestampMs: Int,
        confidence: Double = 0.9,
        frequencyHz: Double? = 440,
        writtenOctave: Int = 4,
        isValidForRecording: Bool? = nil
    ) -> PitchFrame {
        let rms = note == nil ? 0 : 0.08
        return PitchFrame(
            timestampMs: timestampMs,
            frequencyHz: frequencyHz,
            confidence: confidence,
            rms: rms,
            centsDeviation: cents,
            tuningStatus: BrassTuneCore.tuningStatus(cents: cents, confidence: confidence, rms: rms),
            writtenNoteName: note,
            writtenOctave: note == nil ? nil : writtenOctave,
            isValidForRecording: isValidForRecording ?? (note != nil && cents != nil && confidence >= 0.95)
        )
    }

    private func makeTinyPNGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            UIColor.white.setStroke()
            context.cgContext.move(to: CGPoint(x: 2, y: 4))
            context.cgContext.addLine(to: CGPoint(x: 14, y: 4))
            context.cgContext.strokePath()
        }
        return try XCTUnwrap(image.pngData())
    }

    private func makePDFData(pageCount: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 144, height: 144)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for pageNumber in 1...pageCount {
                context.beginPage()
                "Page \(pageNumber)".draw(
                    at: CGPoint(x: 16, y: 16),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                )
            }
        }
    }

    private func testPitchClass(_ note: String) -> Int? {
        let normalized = note
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        return [
            "C": 0, "B#": 0,
            "C#": 1, "Db": 1,
            "D": 2,
            "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4,
            "E#": 5, "F": 5,
            "F#": 6, "Gb": 6,
            "G": 7,
            "G#": 8, "Ab": 8,
            "A": 9,
            "A#": 10, "Bb": 10,
            "B": 11, "Cb": 11,
        ][normalized]
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct TestAPIResponse: Decodable {
    let ok: Bool?
}

private struct CapturedRequest {
    let method: String
    let path: String
    let authorization: String?
    let body: Data?
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
    }
    return result
}
