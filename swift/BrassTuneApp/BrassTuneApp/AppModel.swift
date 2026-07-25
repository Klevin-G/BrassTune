import Combine
import CryptoKit
import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

@MainActor
enum AppAudioOwnershipHandoff {
    static func prepareForTonePlayback(
        cancelPendingRecordingStart: () -> Void,
        isRecording: () -> Bool,
        stopRecording: () -> Void
    ) {
        cancelPendingRecordingStart()
        if isRecording() {
            stopRecording()
        }
    }
}

struct NativeRecordingFileStore {
    static let defaultStorageDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("BrassTune/SessionRecordings", isDirectory: true)

    let storageDirectory: URL
    private let removeItem: (URL) throws -> Void
    private let fileExists: (URL) -> Bool
    private let isPlayableAudio: (URL) -> Bool

    init(
        storageDirectory: URL,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        isPlayableAudio: @escaping (URL) -> Bool = {
            (try? NativeRecordingPlaybackDriver.live(url: $0)) != nil
        }
    ) {
        self.storageDirectory = storageDirectory
        self.removeItem = removeItem
        self.fileExists = fileExists
        self.isPlayableAudio = isPlayableAudio
    }

    func destinationURL(id: UUID = UUID()) -> URL {
        storageDirectory.appendingPathComponent("\(id.uuidString).caf", isDirectory: false)
    }

    func availableURL(_ retainedURL: URL?) -> URL? {
        guard let retainedURL,
              owns(retainedURL),
              retainedURL.pathExtension.lowercased() == "caf",
              fileExists(retainedURL),
              isPlayableAudio(retainedURL) else {
            return nil
        }
        return retainedURL.standardizedFileURL
    }

    func owns(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let base = storageDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        return candidate.deletingLastPathComponent() == base
    }

    func deleteRecording(at retainedURL: URL?) throws {
        guard let retainedURL, owns(retainedURL), fileExists(retainedURL) else { return }
        try removeItem(retainedURL)
    }

    func deleteAllStoredFiles() throws {
        guard fileExists(storageDirectory) else { return }
        try removeItem(storageDirectory)
    }
}

enum PendingAppDestination: Equatable {
    case classes
}

@MainActor
final class AppModel: ObservableObject {
    /// Third-party native OAuth is intentionally not part of this shipping
    /// configuration. Keeping this local gate separate from Supabase's remote
    /// provider settings prevents a server-side toggle from exposing a
    /// Google-only native flow while Sign in with Apple is deferred.
    static let nativeThirdPartySignInEnabled = false

    @Published var config: AppConfig = .fromProcessEnvironment()
    @Published var authState: AuthState = .signedOut
    @Published private(set) var persistenceAccessState: PersistenceAccessState = .restoringIdentity
    @Published var selectedInstrumentId = "trumpet" { didSet { persistLocalData() } }
    @Published var referencePitchHz = 440.0 { didSet { persistLocalData() } }
    @Published var sessions: [PracticeSession] = [] { didSet { persistLocalData() } }
    @Published var scores: [ImportedScore] = [] { didSet { persistLocalData() } }
    @Published var activeScoreID: ImportedScore.ID? { didSet { persistLocalData() } }
    @Published var recordingSource: PracticeSessionSource = NativeAudioEngine.defaultRecordingSource
    @Published var metronome = MetronomeSettings() { didSet { persistLocalData(); restartMetronomeIfNeeded() } }
    @Published var practiceFeatures = AppModel.freshPracticeFeatureState() { didSet { persistLocalData() } }
    @Published var successHapticsEnabled = true { didSet { persistLocalData() } }
    @Published var appLanguage: AppLanguage = .system {
        didSet {
            NativeLocalization.language = AppLanguage.launchOverride ?? appLanguage
            persistLocalData()
        }
    }
    @Published private(set) var gatewayCompleted = false { didSet { persistLocalData() } }
    @Published private(set) var metronomeRunning = false
    @Published private(set) var metronomeTick = 0
    @Published private(set) var metronomeCountInRemaining = 0
    @Published private(set) var metronomeLastPulseWasAccented = false
    @Published private(set) var recordingStartInProgress = false
    @Published var selectedPlayAlongExerciseID = PlayAlongExercise.defaultExercise.id
    @Published private(set) var playAlongPhase: PlayAlongPhase = .idle
    @Published private(set) var playAlongStartInProgress = false
    @Published private(set) var playAlongSession: PlayAlongSession?
    @Published private(set) var playAlongGrade: PlayAlongGrade?
    @Published var ensembles: [EnsembleSummary] = []
    @Published var selectedEnsembleID: EnsembleSummary.ID?
    @Published private(set) var ensembleInvitations: [EnsembleInvitation] = []
    @Published private(set) var selectedEnsembleDetail: EnsembleSummary?
    @Published private(set) var selectedEnsembleRoster: [EnsembleRosterStudent] = []
    @Published private(set) var selectedEnsembleAggregate: EnsembleAggregateSummary?
    @Published private(set) var ensemblesLoading = false
    @Published private(set) var ensembleMutationInProgress = false
    @Published private(set) var ensembleStatusMessage: String?
    @Published private(set) var tutorialCompleted = false { didSet { persistLocalData() } }
    @Published private(set) var tutorialPresentationRequest = 0
    @Published private(set) var authOperationInProgress = false
    @Published private(set) var authNotice: String?
    @Published private(set) var authNoticeIsError = false
    @Published private(set) var authProviderConfiguration: AuthProviderConfiguration?
    @Published private(set) var authProviderConfigurationLoading = false
    @Published private(set) var authProviderRecoveryMessage: String?
    @Published var lastError: UserVisibleError?
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var guestProgressSafetyPromptEligible = false
    @Published private(set) var persistedPracticeSuccessSequence = 0
    @Published private(set) var pendingDestination: PendingAppDestination?
    @Published private(set) var microphoneRationaleSeen = false { didSet { persistLocalData() } }

    let audioEngine: NativeAudioEngine
    let recordingPlayer: NativeRecordingPlayer
    let apiClient: APIClient
    let authService: AuthService
    private let guestPersistenceStore: NativePersistenceStore
    private var persistenceStore: NativePersistenceStore
    private let guestScoreStorageDirectory: URL
    private let guestRecordingStorageDirectory: URL
    private var scoreImporter: NativeScoreImportService
    private var recordingFileStore: NativeRecordingFileStore
    private let scoreFileRemover: (URL) throws -> Void
    private let recordingFileRemover: (URL) throws -> Void
    private let pendingAccountPurgeStore: PendingDigestStore
    private let pendingCredentialRemovalStore: PendingDigestStore
    private let persistenceWriter: NativePersistenceWriter
    private var activeStorageNamespace: NativeStorageNamespace = .guest
    private let metronomeOutput: NativeMetronomeOutput
    private var isRestoringLocalState = false
    private var metronomeTimer: Timer?
    private var tapTempoEvents: [Date] = []
    private var audioFrameCancellable: AnyCancellable?
    private var audioRecordingCancellable: AnyCancellable?
    private var playAlongFixtureTask: Task<Void, Never>?
    private var playAlongUsesFixture = false
    private var playAlongStartToken: UUID?
    private var recordingStartToken: UUID?
    private var ensembleLoadGeneration = 0
    private var activeEnsembleLoadID: UUID?
    private var persistenceWriteGeneration = 0
    private var persistedSessionIDs = Set<PracticeSession.ID>()
    private var retainedUnexpectedCaptureIDs = Set<NativeLiveCapture.ID>()
    private var guestProgressSafetyPromptHandled = false
    private let classAccessTokenProvider: (@MainActor (AppConfig) async throws -> String?)?

    init(
        persistenceStore: NativePersistenceStore = .live(),
        scoreStorageDirectory: URL? = nil,
        recordingStorageDirectory: URL? = nil,
        scoreFileRemover: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        recordingFileRemover: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        pendingAccountPurgeStore: PendingDigestStore = .live(key: "native.pending-account-purge-digests"),
        pendingCredentialRemovalStore: PendingDigestStore = .live(key: "native.pending-credential-removal-digests"),
        apiClient: APIClient = APIClient(),
        authService: AuthService = AuthService(),
        audioSessionCoordinator: NativeAudioSessionCoordinator = .shared,
        audioEngine: NativeAudioEngine? = nil,
        recordingPlayer: NativeRecordingPlayer? = nil,
        classAccessTokenProvider: (@MainActor (AppConfig) async throws -> String?)? = nil
    ) {
        NativeLocalization.language = AppLanguage.launchOverride ?? .system
        let resolvedScoreStorageDirectory = scoreStorageDirectory ?? NativeScoreImportService.defaultStorageDirectory
        let resolvedRecordingStorageDirectory = recordingStorageDirectory ?? NativeRecordingFileStore.defaultStorageDirectory
        self.guestPersistenceStore = persistenceStore
        self.persistenceStore = persistenceStore
        self.guestScoreStorageDirectory = resolvedScoreStorageDirectory
        self.guestRecordingStorageDirectory = resolvedRecordingStorageDirectory
        self.scoreFileRemover = scoreFileRemover
        self.recordingFileRemover = recordingFileRemover
        self.pendingAccountPurgeStore = pendingAccountPurgeStore
        self.pendingCredentialRemovalStore = pendingCredentialRemovalStore
        self.persistenceWriter = NativePersistenceWriter()
        self.scoreImporter = NativeScoreImportService(
            storageDirectory: resolvedScoreStorageDirectory,
            removeItem: scoreFileRemover
        )
        self.recordingFileStore = NativeRecordingFileStore(
            storageDirectory: resolvedRecordingStorageDirectory,
            removeItem: recordingFileRemover
        )
        self.apiClient = apiClient
        self.authService = authService
        self.audioEngine = audioEngine ?? NativeAudioEngine(audioSessionCoordinator: audioSessionCoordinator)
        self.recordingPlayer = recordingPlayer ?? NativeRecordingPlayer(audioSessionCoordinator: audioSessionCoordinator)
        self.metronomeOutput = NativeMetronomeOutput(audioSessionCoordinator: audioSessionCoordinator)
        self.classAccessTokenProvider = classAccessTokenProvider
        retryPendingAccountPurges()
        observeAudioFrames()
        self.audioEngine.setTonePlaybackPreparation { [weak self] in
            guard let self else { return }
            self.recordingPlayer.stopAndUnload()
            AppAudioOwnershipHandoff.prepareForTonePlayback(
                cancelPendingRecordingStart: self.cancelRecordingStart,
                isRecording: { self.audioEngine.recording },
                stopRecording: self.stopRecording
            )
        }
        self.audioEngine.setUnexpectedCaptureCompletion { [weak self] capture in
            self?.retainUnexpectedLiveCapture(capture)
        }
        self.recordingPlayer.setPlaybackPreparation { [weak self] in
            self?.prepareForRecordingPlayback()
        }
    }

    private static func freshPracticeFeatureState() -> PracticeFeatureState {
        var state = PracticeFeatureState()
        state.weeklyGoal = WeeklyPracticeGoal(targetMinutes: 15, targetSessions: 3)
        return state
    }

    static let demoEnsembles = [
        EnsembleSummary(
            id: 1,
            name: "Demo brass studio",
            directorUserID: nil,
            joinCode: nil,
            viewerRole: "student",
            viewerCanLeave: true,
            viewerCanManage: false,
            createdAt: nil,
            updatedAt: nil
        ),
        EnsembleSummary(
            id: 2,
            name: "Second demo class",
            directorUserID: nil,
            joinCode: nil,
            viewerRole: "owner",
            viewerCanLeave: false,
            viewerCanManage: true,
            createdAt: nil,
            updatedAt: nil
        )
    ]

    var analyticsSnapshot: AnalyticsSnapshot {
        AnalyticsSnapshot(sessions: sessions)
    }

    var playAlongExercises: [PlayAlongExercise] {
        var exercises = PlayAlongExercise.library + practiceFeatures.customExercises.map(\.exercise)
        if let generated = weakTransitionInsight?.exercise,
           !exercises.contains(where: { $0.id == generated.id }) {
            exercises.append(generated)
        }
        return exercises
    }

    var selectedPlayAlongExercise: PlayAlongExercise {
        playAlongExercises.first { $0.id == selectedPlayAlongExerciseID } ?? .defaultExercise
    }

    var metronomeTemporarilyMutedForRecording: Bool {
        audioEngine.recording && audioEngine.activeSource == .live
    }

    var testFixturesEnabled: Bool {
        NativeAudioEngine.testFixturesEnabled
    }

    var activeScore: ImportedScore? {
        guard let activeScoreID else {
            return scores.first
        }
        return scores.first { $0.id == activeScoreID } ?? scores.first
    }

    var selectedScoreForPracticeLabel: String {
        activeScore?.title ?? "No score attached"
    }

    var accountFeaturesEnabled: Bool {
        config.hasUsableAccountConfiguration
    }

    var accountUnavailableMessage: String? {
        accountFeaturesEnabled
            ? nil
            : NativeLocalization.string("Practice as a guest today. Online backup and Classes will appear when account access is available.")
    }

    var appleSignInAvailable: Bool {
        Self.nativeThirdPartySignInEnabled
            && accountFeaturesEnabled
            && authProviderConfiguration?.apple == true
    }

    var googleSignInAvailable: Bool {
        Self.nativeThirdPartySignInEnabled
            && accountFeaturesEnabled
            && authProviderConfiguration?.google == true
    }

    func resetForUITesting() {
        try? authService.deleteStoredAuth()
        activateStorageNamespace(.guest)
        authState = .guest
        let exercisesEntryFlow = ProcessInfo.processInfo.arguments.contains("UITEST_ENTRY_FLOW")
        gatewayCompleted = !exercisesEntryFlow
        tutorialCompleted = !exercisesEntryFlow
        appLanguage = .system
        tutorialPresentationRequest = 0
        authOperationInProgress = false
        authNotice = nil
        authNoticeIsError = false
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440.0
        let clearedLocalArtifacts = clearLocalPracticeArtifacts()
        resetPlayAlong()
        recordingSource = NativeAudioEngine.defaultRecordingSource
        metronome = MetronomeSettings()
        practiceFeatures = Self.freshPracticeFeatureState()
        successHapticsEnabled = true
        microphoneRationaleSeen = !ProcessInfo.processInfo.arguments.contains("UITEST_MIC_RATIONALE")
        guestProgressSafetyPromptHandled = false
        guestProgressSafetyPromptEligible = false
        pendingDestination = nil
        persistedPracticeSuccessSequence = 0
        persistedSessionIDs = []
        stopMetronome()
        ensembles = NativeAudioEngine.testFixturesEnabled ? Self.demoEnsembles : []
        selectedEnsembleID = ensembles.first?.id
        ensembleInvitations = []
        selectedEnsembleDetail = nil
        selectedEnsembleRoster = []
        selectedEnsembleAggregate = nil
        ensembleStatusMessage = nil
        if clearedLocalArtifacts {
            lastError = nil
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_PERSISTENCE_ERROR") {
            persistenceWriter.flush()
            persistenceWriteGeneration &+= 1
            persistenceErrorMessage = NativeLocalization.string("BrassTune couldn't save your latest changes on this device. Keep the app open, export your data if needed, and try again.")
        }
    }

    func enterGuestDemo(presentTutorial: Bool = true) {
        guard activateStorageNamespace(.guest) else {
            authState = .signedOut
            return
        }
        authState = .guest
        ensembles.removeAll()
        selectedEnsembleID = nil
        ensembleInvitations = []
        selectedEnsembleDetail = nil
        selectedEnsembleRoster = []
        selectedEnsembleAggregate = nil
        ensembleStatusMessage = nil
        authNotice = nil
        authNoticeIsError = false
        lastError = nil
        gatewayCompleted = true
        if presentTutorial {
            requestTutorialPresentation()
        }
    }

    func requestTutorialPresentation() {
        tutorialPresentationRequest &+= 1
    }

    func requestClassDestination() {
        pendingDestination = .classes
    }

    func clearPendingDestination() {
        pendingDestination = nil
    }

    func consumePendingDestination() -> PendingAppDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    func clearAuthNotice() {
        authNotice = nil
        authNoticeIsError = false
        lastError = nil
    }

    func markGuestProgressSafetyPromptHandled() {
        guard !guestProgressSafetyPromptHandled else {
            guestProgressSafetyPromptEligible = false
            return
        }
        guestProgressSafetyPromptHandled = true
        guestProgressSafetyPromptEligible = false
        persistLocalData()
    }

    func markMicrophoneRationaleSeen() {
        microphoneRationaleSeen = true
    }

    func flushPendingPersistence() {
        persistenceWriter.flush()
    }

    func completeGateway() {
        gatewayCompleted = true
    }

    func completeTutorial() {
        guard persistenceAccessState.canPersist else { return }
        tutorialCompleted = true
    }

    func signOut() async {
        var signOutError: Error?
        let accountDigest = activeStorageNamespace.accountDigest
        if let accountDigest { pendingCredentialRemovalStore.enqueue(accountDigest) }
        do {
            try await authService.signOut(config: config)
        } catch {
            signOutError = error
        }
        let remainingSession: AuthSession?
        do {
            remainingSession = try authService.restoreSessionOrThrow()
        } catch {
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(UserVisibleError.secureStorageUnavailable)
            return
        }
        if remainingSession == nil, let accountDigest {
            pendingCredentialRemovalStore.remove(accountDigest)
        }
        transitionToUnauthenticated(.signedOut)
        if let signOutError {
            if remainingSession != nil {
                setAuthFailure(UserVisibleError.secureStorageDeletionFailed)
            } else {
                setAuthFailure(signOutError)
                authNotice = NativeLocalization.string("Signed out on this device. BrassTune couldn't confirm server logout, so try again online before using a shared device.")
            }
        } else {
            lastError = nil
            setAuthNotice(NativeLocalization.string("Signed out."))
        }
    }

    func restoreSession() async {
        let storedSession: AuthSession?
        do {
            storedSession = try authService.restoreSessionOrThrow()
        } catch {
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(UserVisibleError.secureStorageUnavailable)
            return
        }
        guard let storedSession else {
            guard activateStorageNamespace(.guest) else {
                authState = .signedOut
                return
            }
            authState = .guest
            return
        }
        let storedNamespace = NativeStorageNamespace.account(userID: storedSession.userID)
        if let digest = storedNamespace.accountDigest,
           pendingCredentialRemovalStore.pendingDigests.contains(digest) {
            do {
                try authService.deleteStoredAuth()
                pendingCredentialRemovalStore.remove(digest)
                transitionToUnauthenticated(.signedOut)
                lastError = nil
                setAuthNotice(NativeLocalization.string("Signed out."))
            } catch {
                activateStorageNamespace(.guest)
                authState = .signedOut
                setAuthFailure(UserVisibleError.secureStorageDeletionFailed)
            }
            return
        }
        guard prepareStorageNamespace(.account(userID: storedSession.userID)) else {
            authState = .signedOut
            return
        }
        guard config.hasUsableAccountConfiguration else {
            do {
                try authService.signOut()
            } catch {
                transitionToUnauthenticated(.signedOut)
                setAuthFailure(UserVisibleError.secureStorageDeletionFailed)
                return
            }
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(UserVisibleError.missingAuthConfiguration)
            return
        }
        do {
            if let session = try await authService.refreshStoredSession(config: config) {
                let namespace = NativeStorageNamespace.account(userID: session.userID)
                guard activateStorageNamespace(namespace) else { return }
                authState = .signedIn(email: session.email)
                lastError = nil
            }
        } catch is CancellationError {
            return
        } catch {
            if Self.isOfflineAuthFailure(error) {
                do {
                    if let session = try authService.unexpiredStoredSession() {
                        guard activateStorageNamespace(.account(userID: session.userID)) else { return }
                        authState = .signedIn(email: session.email)
                        lastError = (error as? UserVisibleError) ?? .networkUnavailable
                        authNotice = NativeLocalization.string("You're offline. BrassTune kept your unexpired sign-in for local practice; online account features may be unavailable.")
                        authNoticeIsError = true
                        return
                    }
                } catch {
                    transitionToUnauthenticated(.signedOut)
                    setAuthFailure(UserVisibleError.secureStorageUnavailable)
                    return
                }
            }
            if Self.isRetryableAuthRefreshFailure(error) {
                transitionToUnauthenticated(.signedOut)
                setAuthFailure(error)
                return
            }
            try? authService.signOut()
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(error)
        }
    }

    func loadEnsembles() async {
        if NativeAudioEngine.testFixturesEnabled {
            if ensembles.isEmpty {
                ensembles = Self.demoEnsembles
            }
            selectAvailableEnsemble(preferredID: selectedEnsembleID)
            return
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch is CancellationError {
            return
        } catch {
            handleClassAuthOrNetworkError(error)
            return
        }
        guard !token.isEmpty else {
            ensembles = []
            selectedEnsembleID = nil
            return
        }
        ensembleLoadGeneration += 1
        let generation = ensembleLoadGeneration
        let loadID = UUID()
        activeEnsembleLoadID = loadID
        ensemblesLoading = true
        defer {
            if activeEnsembleLoadID == loadID {
                ensemblesLoading = false
                activeEnsembleLoadID = nil
            }
        }
        do {
            let loaded = try await apiClient.request(
                [EnsembleSummary].self,
                path: "/api/ensemble/groups",
                config: config,
                bearerToken: token
            )
            guard !Task.isCancelled, generation == ensembleLoadGeneration else { return }
            ensembles = loaded
            selectAvailableEnsemble(preferredID: selectedEnsembleID)
            if selectedEnsembleDetail?.id != selectedEnsembleID {
                selectedEnsembleDetail = nil
                selectedEnsembleRoster = []
                selectedEnsembleAggregate = nil
            }
            ensembleStatusMessage = nil
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == ensembleLoadGeneration else { return }
            handleClassAuthOrNetworkError(error)
        }
    }

    func loadClassWorkspace() async {
        await loadEnsembles()
        guard !Task.isCancelled else { return }
        await loadEnsembleInvitations()
        guard !Task.isCancelled, let selectedEnsembleID else { return }
        await loadSelectedEnsembleDetails(id: selectedEnsembleID)
    }

    func loadEnsembleInvitations() async {
        if NativeAudioEngine.testFixturesEnabled {
            if ProcessInfo.processInfo.arguments.contains("UITEST_CLASS_FLOWS") {
                ensembleInvitations = [
                    EnsembleInvitation(
                        memberID: 901,
                        groupID: 3,
                        groupName: "Invited studio",
                        instrumentID: "unassigned",
                        roleInGroup: "student",
                        invitedAt: nil,
                        directorName: "Director Rivera"
                    )
                ]
            } else {
                ensembleInvitations = []
            }
            return
        }
        let token: String
        do {
            token = try await validClassAccessToken()
            let response = try await apiClient.request(
                EnsembleInvitationList.self,
                path: "/api/ensemble/invitations",
                config: config,
                bearerToken: token
            )
            guard !Task.isCancelled else { return }
            ensembleInvitations = response.invitations
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            handleClassAuthOrNetworkError(error)
        }
    }

    func loadSelectedEnsembleDetails(id: EnsembleSummary.ID) async {
        guard selectedEnsembleID == id,
              let summary = ensembles.first(where: { $0.id == id }) else { return }
        if NativeAudioEngine.testFixturesEnabled {
            let member = EnsembleMember(
                id: 101,
                groupID: id,
                userID: 501,
                username: "demo-student",
                displayName: "Demo Student",
                instrumentID: "trumpet",
                roleInGroup: "student",
                status: "active",
                isCurrentUser: !summary.viewerCanManage,
                activeSince: nil,
                createdAt: nil
            )
            var detail = summary
            detail.members = [member]
            detail.rosterScope = summary.viewerCanManage ? "full" : "self"
            selectedEnsembleDetail = detail
            selectedEnsembleRoster = summary.viewerCanManage
                ? [
                    EnsembleRosterStudent(
                        memberID: member.id,
                        username: member.username,
                        displayName: member.displayName,
                        instrumentID: member.instrumentID,
                        status: member.status,
                        roleInGroup: member.roleInGroup,
                        sessionsCount: 3,
                        practiceMinutes: 24,
                        averageAbsCents: 6.5,
                        inTunePercentage: 82,
                        lastPracticeAt: nil
                    )
                ]
                : []
            selectedEnsembleAggregate = summary.viewerCanManage
                ? EnsembleAggregateSummary(
                    groupID: id,
                    sessionCount: 3,
                    sections: [
                        EnsembleSectionSummary(
                            instrumentID: "trumpet",
                            sessionCount: 3,
                            practiceMinutes: 24,
                            averageAbsCents: 6.5
                        )
                    ],
                    overall: EnsembleSectionSummary(
                        instrumentID: "all",
                        sessionCount: 3,
                        practiceMinutes: 24,
                        averageAbsCents: 6.5
                    )
                )
                : nil
            return
        }

        let token: String
        do {
            token = try await validClassAccessToken()
            let detail = try await apiClient.request(
                EnsembleSummary.self,
                path: "/api/ensemble/groups/\(id)",
                config: config,
                bearerToken: token
            )
            guard !Task.isCancelled, selectedEnsembleID == id else { return }
            selectedEnsembleDetail = detail
            selectedEnsembleRoster = []
            selectedEnsembleAggregate = nil
            if detail.viewerCanManage {
                async let rosterRequest = apiClient.request(
                    EnsembleRoster.self,
                    path: "/api/ensemble/groups/\(id)/roster",
                    config: config,
                    bearerToken: token
                )
                async let aggregateRequest = apiClient.request(
                    EnsembleAggregateSummary.self,
                    path: "/api/ensemble/groups/\(id)/summary",
                    config: config,
                    bearerToken: token
                )
                let (roster, aggregate) = try await (rosterRequest, aggregateRequest)
                guard !Task.isCancelled, selectedEnsembleID == id else { return }
                selectedEnsembleRoster = roster.students
                selectedEnsembleAggregate = aggregate
            }
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedEnsembleID == id else { return }
            handleClassAuthOrNetworkError(error)
        }
    }

    @discardableResult
    func createEnsemble(name: String) async -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(normalizedName.count) else {
            lastError = .apiRequestFailed(
                statusCode: 422,
                message: NativeLocalization.string("Enter a class name with 2-80 characters.")
            )
            return false
        }
        if NativeAudioEngine.testFixturesEnabled {
            let nextID = (ensembles.map(\.id).max() ?? 0) + 1
            let created = EnsembleSummary(
                id: nextID,
                name: normalizedName,
                directorUserID: nil,
                joinCode: "DEMO\(nextID)",
                viewerRole: "owner",
                viewerCanLeave: false,
                viewerCanManage: true,
                createdAt: nil,
                updatedAt: nil
            )
            ensembles.append(created)
            ensembles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            selectedEnsembleID = created.id
            ensembleStatusMessage = NativeLocalization.format("Created %@.", created.name)
            await loadSelectedEnsembleDetails(id: created.id)
            return true
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["name": normalizedName])
            let response = try await apiClient.request(
                EnsembleCreatedResponse.self,
                path: "/api/ensemble/groups",
                method: "POST",
                body: body,
                config: config,
                bearerToken: token
            )
            selectedEnsembleID = response.id
            await loadClassWorkspace()
            ensembleStatusMessage = NativeLocalization.format("Created %@.", response.name)
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    @discardableResult
    func inviteEnsembleMember(
        groupID: EnsembleSummary.ID,
        username: String,
        instrumentID: String?
    ) async -> Bool {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        guard (3...32).contains(normalizedUsername.count),
              normalizedUsername.unicodeScalars.allSatisfy(allowed.contains) else {
            lastError = .apiRequestFailed(
                statusCode: 422,
                message: NativeLocalization.string("Enter a valid username using letters, numbers, underscores, or hyphens.")
            )
            return false
        }
        if NativeAudioEngine.testFixturesEnabled {
            ensembleStatusMessage = NativeLocalization.format("Invitation sent to %@.", "@\(normalizedUsername)")
            return true
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            var payload: [String: Any] = [
                "username": normalizedUsername,
                "role_in_group": "student",
            ]
            if let instrumentID, !instrumentID.isEmpty {
                payload["instrument_id"] = instrumentID
            }
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await apiClient.request(
                EnsembleMember.self,
                path: "/api/ensemble/groups/\(groupID)/members/by-username",
                method: "POST",
                body: body,
                config: config,
                bearerToken: token
            )
            await loadSelectedEnsembleDetails(id: groupID)
            ensembleStatusMessage = NativeLocalization.format("Invitation sent to %@.", "@\(normalizedUsername)")
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    @discardableResult
    func rotateEnsembleJoinCode(id: EnsembleSummary.ID) async -> Bool {
        if NativeAudioEngine.testFixturesEnabled {
            let code = "NEW\(id)CODE"
            updateEnsembleJoinCode(id: id, code: code)
            ensembleStatusMessage = NativeLocalization.string("A new class code is ready. The previous code no longer works.")
            return true
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let response = try await apiClient.request(
                EnsembleJoinCodeResponse.self,
                path: "/api/ensemble/groups/\(id)/join-code/rotate",
                method: "POST",
                config: config,
                bearerToken: token
            )
            updateEnsembleJoinCode(id: response.groupID, code: response.joinCode)
            ensembleStatusMessage = NativeLocalization.string("A new class code is ready. The previous code no longer works.")
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    @discardableResult
    func respondToEnsembleInvitation(
        memberID: EnsembleInvitation.ID,
        accept: Bool,
        instrumentID: String? = nil
    ) async -> Bool {
        guard let invitation = ensembleInvitations.first(where: { $0.memberID == memberID }) else { return false }
        if accept, (instrumentID ?? "").isEmpty {
            lastError = .apiRequestFailed(
                statusCode: 422,
                message: NativeLocalization.string("Choose your instrument before accepting.")
            )
            return false
        }
        if NativeAudioEngine.testFixturesEnabled {
            ensembleInvitations.removeAll { $0.memberID == memberID }
            if accept {
                let joined = EnsembleSummary(
                    id: invitation.groupID,
                    name: invitation.groupName,
                    directorUserID: nil,
                    joinCode: nil,
                    viewerRole: "student",
                    viewerCanLeave: true,
                    viewerCanManage: false,
                    createdAt: nil,
                    updatedAt: nil
                )
                ensembles.removeAll { $0.id == joined.id }
                ensembles.append(joined)
                selectedEnsembleID = joined.id
                ensembleStatusMessage = NativeLocalization.format("Joined %@.", joined.name)
            } else {
                ensembleStatusMessage = NativeLocalization.format("Declined the invitation to %@.", invitation.groupName)
            }
            return true
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let path = accept
                ? "/api/ensemble/invitations/\(memberID)/accept"
                : "/api/ensemble/invitations/\(memberID)/decline"
            let body = accept
                ? try JSONSerialization.data(withJSONObject: ["instrument_id": instrumentID ?? selectedInstrumentId])
                : nil
            _ = try await apiClient.request(
                EnsembleInvitationDecisionResponse.self,
                path: path,
                method: "POST",
                body: body,
                config: config,
                bearerToken: token
            )
            ensembleInvitations.removeAll { $0.memberID == memberID }
            if accept {
                selectedEnsembleID = invitation.groupID
                await loadClassWorkspace()
                ensembleStatusMessage = NativeLocalization.format("Joined %@.", invitation.groupName)
            } else {
                ensembleStatusMessage = NativeLocalization.format("Declined the invitation to %@.", invitation.groupName)
            }
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    @discardableResult
    func removeEnsembleMember(groupID: EnsembleSummary.ID, memberID: EnsembleMember.ID) async -> Bool {
        if NativeAudioEngine.testFixturesEnabled {
            selectedEnsembleDetail?.members?.removeAll { $0.id == memberID }
            selectedEnsembleRoster.removeAll { $0.memberID == memberID }
            ensembleStatusMessage = NativeLocalization.string("Member removed.")
            return true
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let response = try await apiClient.request(
                EnsembleMemberRemovalResponse.self,
                path: "/api/ensemble/groups/\(groupID)/members/\(memberID)",
                method: "DELETE",
                config: config,
                bearerToken: token
            )
            guard response.removed else { throw UserVisibleError.malformedResponse }
            await loadSelectedEnsembleDetails(id: groupID)
            ensembleStatusMessage = NativeLocalization.string("Member removed.")
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    private func updateEnsembleJoinCode(id: EnsembleSummary.ID, code: String) {
        if let index = ensembles.firstIndex(where: { $0.id == id }) {
            ensembles[index].joinCode = code
        }
        if selectedEnsembleDetail?.id == id {
            selectedEnsembleDetail?.joinCode = code
        }
    }

    @discardableResult
    func joinEnsemble(code: String) async -> Bool {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard (4...16).contains(normalizedCode.count) else {
            lastError = .apiRequestFailed(statusCode: 422, message: NativeLocalization.string("Enter the 4-16 character class code from your teacher."))
            return false
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "code": normalizedCode,
                "instrument_id": selectedInstrumentId,
            ])
            let response = try await apiClient.request(
                EnsembleJoinResponse.self,
                path: "/api/ensemble/join",
                method: "POST",
                body: body,
                config: config,
                bearerToken: token
            )
            selectedEnsembleID = response.groupID
            ensembleLoadGeneration += 1
            if !ensembles.contains(where: { $0.id == response.groupID }) {
                ensembles.append(
                    EnsembleSummary(
                        id: response.groupID,
                        name: response.groupName,
                        directorUserID: nil,
                        joinCode: nil,
                        viewerRole: "student",
                        viewerCanLeave: true,
                        viewerCanManage: false,
                        createdAt: nil,
                        updatedAt: nil
                    )
                )
                ensembles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            await loadEnsembles()
            ensembleStatusMessage = NativeLocalization.format("Joined %@.", response.groupName)
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    @discardableResult
    func leaveEnsemble(id: EnsembleSummary.ID) async -> Bool {
        guard let target = ensembles.first(where: { $0.id == id }) else { return false }
        guard target.canLeave else {
            lastError = .apiRequestFailed(
                statusCode: 409,
                message: NativeLocalization.format(
                    "Your %@ role cannot leave this class through self-service.",
                    target.viewerRoleLabel.lowercased()
                )
            )
            return false
        }
        let token: String
        do {
            token = try await validClassAccessToken()
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
        guard !ensembleMutationInProgress else { return false }
        ensembleMutationInProgress = true
        defer { ensembleMutationInProgress = false }
        do {
            let response = try await apiClient.request(
                EnsembleLeaveResponse.self,
                path: "/api/ensemble/groups/\(id)/membership",
                method: "DELETE",
                config: config,
                bearerToken: token
            )
            guard response.left, response.groupID == id else {
                throw UserVisibleError.malformedResponse
            }
            ensembleLoadGeneration += 1
            ensembles.removeAll { $0.id == id }
            selectAvailableEnsemble(preferredID: selectedEnsembleID == id ? nil : selectedEnsembleID)
            if selectedEnsembleDetail?.id == id {
                selectedEnsembleDetail = nil
                selectedEnsembleRoster = []
                selectedEnsembleAggregate = nil
            }
            ensembleStatusMessage = NativeLocalization.format("Left %@.", target.name)
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            handleClassAuthOrNetworkError(error)
            return false
        }
    }

    private func validClassAccessToken() async throws -> String {
        guard classAccessTokenProvider != nil || authState.usesRemoteAccount else {
            throw UserVisibleError.apiRequestFailed(statusCode: 400, message: NativeLocalization.string("Sign in before using classes."))
        }
        let token: String?
        if let classAccessTokenProvider {
            token = try await classAccessTokenProvider(config)
        } else {
            token = try await authService.validAccessToken(config: config)
        }
        guard let token, !token.isEmpty else {
            throw UserVisibleError.apiRequestFailed(statusCode: 401, message: NativeLocalization.string("Sign in before using classes."))
        }
        return token
    }

    private func handleClassAuthOrNetworkError(_ error: Error) {
        let visible = (error as? UserVisibleError) ?? .networkUnavailable
        if case .apiRequestFailed(let statusCode, _) = visible, statusCode == 401 {
            let expired = UserVisibleError.apiRequestFailed(
                statusCode: 401,
                message: NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
            )
            try? authService.signOut()
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(expired)
            return
        } else if visible == .authenticationFailed {
            try? authService.signOut()
            transitionToUnauthenticated(.signedOut)
            setAuthFailure(visible)
            return
        }
        setAuthFailure(visible)
    }

    private func selectAvailableEnsemble(preferredID: EnsembleSummary.ID?) {
        if let preferredID, ensembles.contains(where: { $0.id == preferredID }) {
            selectedEnsembleID = preferredID
        } else {
            selectedEnsembleID = ensembles.first?.id
        }
    }

    func signIn(email: String, password: String) async {
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        do {
            let session = try await authService.signIn(email: email, password: password, config: config)
            guard activateStorageNamespace(.account(userID: session.userID)) else { return }
            authState = .signedIn(email: session.email)
            gatewayCompleted = true
            lastError = nil
            setAuthNotice(NativeLocalization.string("Signed in."))
        } catch {
            setAuthFailure(error)
        }
    }

    func signUp(email: String, password: String) async {
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        do {
            let session = try await authService.signUp(email: email, password: password, config: config)
            guard activateStorageNamespace(.account(userID: session.userID)) else { return }
            authState = .signedIn(email: session.email)
            gatewayCompleted = true
            lastError = nil
            setAuthNotice(NativeLocalization.string("Signed in."))
            requestTutorialPresentation()
        } catch UserVisibleError.emailConfirmationRequired {
            transitionToUnauthenticated(.emailConfirmationRequired(email: email))
            lastError = nil
            setAuthNotice(NativeLocalization.string("Check your email to confirm this BrassTune account before signing in."))
        } catch {
            setAuthFailure(error)
        }
    }

    func requestPasswordReset(email: String) async {
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        do {
            try await authService.requestPasswordReset(email: email, config: config)
            lastError = nil
            setAuthNotice(NativeLocalization.string(
                "Password reset email sent. Open the secure web reset page from the email, then return to BrassTune and sign in."
            ))
        } catch {
            setAuthFailure(error)
        }
    }

    func loadAuthProviderConfiguration(force: Bool = false) async {
        if !force, authProviderConfiguration != nil { return }
        guard Self.nativeThirdPartySignInEnabled else {
            // Do not ask Supabase for remotely enabled OAuth providers when the
            // native release intentionally ships email/password and guest only.
            authProviderConfiguration = AuthProviderConfiguration(apple: false, google: false)
            authProviderRecoveryMessage = nil
            authProviderConfigurationLoading = false
            return
        }
        guard accountFeaturesEnabled else {
            authProviderConfiguration = nil
            authProviderRecoveryMessage = NativeLocalization.string(
                "Account sign-in needs secure service configuration. You can keep practicing as a guest."
            )
            return
        }
        if ProcessInfo.processInfo.arguments.contains("UITEST_AUTH_PROVIDERS") {
            authProviderConfiguration = AuthProviderConfiguration(apple: false, google: true)
            authProviderRecoveryMessage = NativeLocalization.string(
                "One sign-in provider needs setup. Use an available provider or email and password."
            )
            return
        }
        guard !authProviderConfigurationLoading else { return }
        authProviderConfigurationLoading = true
        authProviderRecoveryMessage = nil
        defer { authProviderConfigurationLoading = false }
        do {
            let providers = try await authService.loadProviderConfiguration(config: config)
            authProviderConfiguration = providers
            if !providers.apple && !providers.google {
                authProviderRecoveryMessage = NativeLocalization.string(
                    "Apple and Google sign-in need provider setup. Email and password still work."
                )
            } else if !providers.apple || !providers.google {
                authProviderRecoveryMessage = NativeLocalization.string(
                    "One sign-in provider needs setup. Use an available provider or email and password."
                )
            }
        } catch is CancellationError {
            return
        } catch {
            authProviderConfiguration = nil
            authProviderRecoveryMessage = NativeLocalization.string(
                "BrassTune couldn't check Apple and Google sign-in. Retry or use email and password."
            )
        }
    }

    func completeAppleSignIn(identityToken: Data, rawNonce: String) async {
        guard appleSignInAvailable else {
            setAuthFailure(UserVisibleError.oauthProviderUnavailable)
            return
        }
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        do {
            let result = try await authService.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, config: config)
            guard activateStorageNamespace(.account(userID: result.session.userID)) else { return }
            authState = .signedIn(email: result.session.email)
            gatewayCompleted = true
            lastError = nil
            switch result.isNewUser {
            case true:
                setAuthNotice(NativeLocalization.string("Signed in with Apple."))
                requestTutorialPresentation()
            case false:
                setAuthNotice(NativeLocalization.string("Signed in with Apple."))
            case nil:
                // Some providers omit account-age timestamps. Touring the
                // unknown case guarantees a newly created identity is not left
                // without help; known returning accounts are not interrupted.
                setAuthNotice(NativeLocalization.string("Signed in with Apple."))
                requestTutorialPresentation()
            }
        } catch {
            setAuthFailure(error)
        }
    }

    func completeGoogleSignIn() async {
        guard googleSignInAvailable else {
            setAuthFailure(UserVisibleError.oauthProviderUnavailable)
            return
        }
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        do {
            let session = try await authService.signInWithGoogle(config: config)
            guard activateStorageNamespace(.account(userID: session.userID)) else { return }
            authState = .signedIn(email: session.email)
            gatewayCompleted = true
            lastError = nil
            setAuthNotice(NativeLocalization.string("Signed in with Google."))
            requestTutorialPresentation()
        } catch is CancellationError {
            // View-lifecycle cancellation is not an authentication failure.
        } catch {
            setAuthFailure(error)
        }
    }

    func reportAuthFailure(_ error: UserVisibleError) {
        setAuthFailure(error)
    }

    private func beginAuthOperation() -> Bool {
        guard !authOperationInProgress else { return false }
        authOperationInProgress = true
        authNotice = nil
        authNoticeIsError = false
        lastError = nil
        return true
    }

    private func setAuthNotice(_ message: String) {
        authNotice = message
        authNoticeIsError = false
    }

    private func setAuthFailure(_ error: Error) {
        let visible = (error as? UserVisibleError) ?? .authenticationFailed
        lastError = visible
        authNotice = visible.localizedDescription
        authNoticeIsError = true
    }

    private static func isOfflineAuthFailure(_ error: Error) -> Bool {
        guard let visible = error as? UserVisibleError else { return false }
        switch visible {
        case .networkUnavailable, .timeout:
            return true
        default:
            return false
        }
    }

    private static func isRetryableAuthRefreshFailure(_ error: Error) -> Bool {
        if isOfflineAuthFailure(error) { return true }
        guard let visible = error as? UserVisibleError,
              case .apiRequestFailed(let statusCode, _) = visible else { return false }
        return statusCode == 408
            || statusCode == 425
            || statusCode == 429
            || (500...599).contains(statusCode)
    }

    func deleteSession(id: PracticeSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if recordingPlayer.loadedURL == availableRecordingURL(for: session) {
            recordingPlayer.stopAndUnload()
        }
        do {
            try recordingFileStore.deleteRecording(at: session.retainedRecordingURL)
        } catch {
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't clear its saved local data, so your practice data was kept. Try again.")
            )
            return
        }
        sessions.removeAll { $0.id == id }
        practiceFeatures.reflections.removeAll { $0.sessionID == id }
    }

    func availableRecordingURL(for session: PracticeSession) -> URL? {
        recordingFileStore.availableURL(session.retainedRecordingURL)
    }

    func toggleRecordingPlayback(for session: PracticeSession) {
        guard let url = availableRecordingURL(for: session) else {
            recordingPlayer.stopAndUnload()
            return
        }
        recordingPlayer.togglePlayback(url: url)
    }

    func stopRecordingPlayback() {
        recordingPlayer.stopAndUnload()
    }

    func exportDataText() -> String {
        var lines = [
            "BrassTune local data export",
            "Account state: \(authState.displayTitle)",
            "Instrument: \(instrumentDisplayName(selectedInstrumentId))",
            "Reference pitch: \(String(format: "%.1f", referencePitchHz)) Hz",
            "Sessions: \(sessions.count)",
            "Scores: \(scores.count)",
            "Metronome: \(metronome.bpm) BPM, \(metronome.meterLabel), sound \(metronome.visualOnly ? "off" : "on")",
            "Custom exercises: \(practiceFeatures.customExercises.count)",
            "Metronome presets: \(practiceFeatures.metronomePresets.count)",
            "Weekly goal: \(practiceFeatures.weeklyGoal.targetMinutes) minutes and \(practiceFeatures.weeklyGoal.targetSessions) sessions",
            "Practice reflections: \(practiceFeatures.reflections.count)",
            "Offline practice packs: \(practicePacks.count)",
        ]
        let analytics = analyticsSnapshot
        if analytics.hasSessions {
            lines.append("Average absolute cents: \(String(format: "%.1f", analytics.averageAbsCents))")
            lines.append("Average in-tune percentage: \(String(format: "%.0f", analytics.averageInTunePercentage))%")
            lines.append("")
            lines.append("Sessions")
            lines.append(contentsOf: sessions.map(\.exportText))
        } else {
            lines.append("No local practice sessions have been recorded.")
        }
        if !scores.isEmpty {
            lines.append("")
            lines.append("Scores")
            lines.append(contentsOf: scores.map(\.exportText))
        }
        return lines.joined(separator: "\n")
    }

    func deleteAccount(confirmation: String) async {
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete my account" else {
            lastError = .accountDeletionRequiresConfirmation
            authNotice = lastError?.localizedDescription
            authNoticeIsError = true
            return
        }
        await deleteAccount()
    }

    func deleteAccount() async {
        guard beginAuthOperation() else { return }
        defer { authOperationInProgress = false }
        let deletedRemoteAccount = authState.usesRemoteAccount
        if deletedRemoteAccount {
            let response: BackendDeletionResponse
            do {
                guard let token = try await authService.validAccessToken(config: config), !token.isEmpty else {
                    throw UserVisibleError.apiRequestFailed(
                        statusCode: 401,
                        message: NativeLocalization.string("Your sign-in expired. Sign in again before deleting your account.")
                    )
                }
                response = try await requestRemoteAccountDeletion(bearerToken: token)
            } catch {
                setAuthFailure(error)
                return
            }

            guard let accountDigest = activeStorageNamespace.accountDigest else {
                setAuthFailure(UserVisibleError.malformedResponse)
                return
            }
            guard response.deleted else {
                if response.deletionStatus == "external_cleanup_queued" {
                    finishRemoteAccountDeletion(accountDigest: accountDigest, providerCleanupQueued: true)
                } else {
                    setAuthFailure(UserVisibleError.apiRequestFailed(
                        statusCode: 500,
                        message: NativeLocalization.string("The class service could not complete this request.")
                    ))
                }
                return
            }
            finishRemoteAccountDeletion(accountDigest: accountDigest, providerCleanupQueued: false)
            return
        }
        let hasStoredCredential: Bool
        do {
            hasStoredCredential = try authService.restoreSessionOrThrow() != nil
        } catch {
            setAuthFailure(UserVisibleError.secureStorageUnavailable)
            return
        }
        resetPlayAlong()
        let clearedLocalArtifacts = clearLocalPracticeArtifacts()
        stopMetronome()
        ensembles.removeAll()
        selectedEnsembleID = nil
        ensembleStatusMessage = nil
        var credentialRemovalFailed = false
        if hasStoredCredential {
            do {
                try authService.deleteStoredAuth()
            } catch {
                credentialRemovalFailed = true
                setAuthFailure(UserVisibleError.secureStorageDeletionFailed)
            }
        }
        transitionToUnauthenticated(.signedOut)
        if clearedLocalArtifacts, !credentialRemovalFailed {
            lastError = nil
            setAuthNotice(NativeLocalization.string("Done"))
        }
    }

    private func requestRemoteAccountDeletion(bearerToken: String) async throws -> BackendDeletionResponse {
        let body = try JSONSerialization.data(withJSONObject: ["confirmation": "delete my account"])
        return try await apiClient.request(
            BackendDeletionResponse.self,
            path: "/api/users/me",
            method: "DELETE",
            body: body,
            config: config,
            bearerToken: bearerToken
        )
    }

    private func finishRemoteAccountDeletion(accountDigest: String, providerCleanupQueued: Bool) {
        // The account namespace must be durable before the purge begins, and no
        // queued save may recreate its state file after deletion completes.
        persistenceWriter.flush()
        persistenceWriteGeneration &+= 1
        pendingAccountPurgeStore.enqueue(accountDigest)
        pendingCredentialRemovalStore.enqueue(accountDigest)
        let purged = retryPendingAccountPurge(accountDigest)
        let credentialsRemoved: Bool
        do {
            try authService.deleteStoredAuth()
            pendingCredentialRemovalStore.remove(accountDigest)
            credentialsRemoved = true
        } catch {
            credentialsRemoved = false
        }
        resetPlayAlong()
        stopMetronome()
        ensembles.removeAll()
        selectedEnsembleID = nil
        ensembleStatusMessage = nil
        transitionToUnauthenticated(.signedOut)
        if purged, credentialsRemoved {
            lastError = nil
            setAuthNotice(NativeLocalization.string(
                providerCleanupQueued
                    ? "Local data was removed. Account-provider cleanup is queued."
                    : "Account and local practice data deleted."
            ))
        } else {
            lastError = credentialsRemoved
                ? .apiRequestFailed(
                    statusCode: 500,
                    message: NativeLocalization.string("Your account was deleted. BrassTune will retry removing its remaining local data the next time the app opens.")
                )
                : .secureStorageDeletionFailed
            let outcome = providerCleanupQueued
                ? NativeLocalization.string(
                    purged
                        ? "Local data was removed. Account-provider cleanup is queued."
                        : "Account-provider cleanup is queued. BrassTune will retry removing its remaining local data the next time the app opens."
                )
                : NativeLocalization.string(
                    purged
                        ? "Account and local practice data deleted."
                        : "Your account was deleted. BrassTune will retry removing its remaining local data the next time the app opens."
                )
            authNotice = credentialsRemoved
                ? outcome
                : "\(outcome) \(UserVisibleError.secureStorageDeletionFailed.localizedDescription)"
            authNoticeIsError = true
        }
    }

    @discardableResult
    private func retryPendingAccountPurge(_ digest: String) -> Bool {
        do {
            try guestPersistenceStore.scoped(accountDigest: digest).clear()
            let scoreDirectory = NativeStorageNamespace.scoreDirectory(
                accountDigest: digest,
                basedAt: guestScoreStorageDirectory
            )
            if FileManager.default.fileExists(atPath: scoreDirectory.path) {
                try scoreFileRemover(scoreDirectory)
            }
            let recordingDirectory = NativeStorageNamespace.recordingDirectory(
                accountDigest: digest,
                basedAt: guestRecordingStorageDirectory
            )
            if FileManager.default.fileExists(atPath: recordingDirectory.path) {
                try recordingFileRemover(recordingDirectory)
            }
            pendingAccountPurgeStore.remove(digest)
            return true
        } catch {
            return false
        }
    }

    private func retryPendingAccountPurges() {
        for digest in pendingAccountPurgeStore.pendingDigests {
            _ = retryPendingAccountPurge(digest)
        }
    }

    func startDemoRecording() {
        guard NativeAudioEngine.testFixturesEnabled else {
            recordingSource = .live
            return
        }
        recordingSource = .sample
        audioEngine.startFixtureRecording(instrumentId: selectedInstrumentId, referencePitchHz: referencePitchHz)
    }

    func stopDemoRecording() {
        guard NativeAudioEngine.testFixturesEnabled else { return }
        let frames = audioEngine.stopFixtureRecording()
        saveRecordedSession(frames: frames, source: .sample)
    }

    func startRecording() async {
        guard !recordingStartInProgress, !audioEngine.recording else { return }
        recordingPlayer.stopAndUnload()
        if playAlongStartInProgress || playAlongPhase == .running {
            stopPlayAlong()
        }
        let startToken = UUID()
        recordingStartToken = startToken
        recordingStartInProgress = true
        defer {
            if recordingStartToken == startToken {
                recordingStartToken = nil
                recordingStartInProgress = false
            }
        }
        lastError = nil
        let allowedSource: PracticeSessionSource = recordingSource == .sample && NativeAudioEngine.testFixturesEnabled ? .sample : .live
        recordingSource = allowedSource
        switch allowedSource {
        case .sample:
            startDemoRecording()
        case .live:
            do {
                let started = try await audioEngine.startLiveRecording(
                    instrumentId: selectedInstrumentId,
                    referencePitchHz: referencePitchHz,
                    recordingURL: recordingFileStore.destinationURL()
                )
                guard recordingStartToken == startToken else {
                    if started {
                        audioEngine.discardLiveRecording()
                    }
                    return
                }
                if !started {
                    lastError = .microphoneDenied
                } else if metronomeRunning {
                    metronomeOutput.stop()
                }
            } catch {
                lastError = .microphoneUnavailable
            }
        }
    }

    func cancelRecordingStart() {
        recordingStartToken = nil
        recordingStartInProgress = false
        audioEngine.cancelPendingLiveStart()
    }

    func stopRecording() {
        guard audioEngine.recording else { return }
        switch audioEngine.activeSource {
        case .live:
            let capture = audioEngine.stopLiveRecording()
            _ = saveRecordedSession(capture: capture, source: .live)
        case .sample:
            stopDemoRecording()
        }
    }

    func startPlayAlong(exerciseID: String? = nil) async {
        guard !playAlongStartInProgress, playAlongPhase != .running else { return }
        recordingPlayer.stopAndUnload()
        cancelRecordingStart()
        let startToken = UUID()
        playAlongStartToken = startToken
        playAlongStartInProgress = true
        defer {
            if playAlongStartToken == startToken {
                playAlongStartToken = nil
            }
            playAlongStartInProgress = false
        }
        lastError = nil
        if let exerciseID,
           playAlongExercises.contains(where: { $0.id == exerciseID }) {
            selectedPlayAlongExerciseID = exerciseID
        }
        if audioEngine.recording {
            stopRecording()
        }

        playAlongSession = nil
        playAlongGrade = nil
        playAlongPhase = .idle
        recordingSource = .live
        if NativeAudioEngine.testFixturesEnabled {
            playAlongSession = PlayAlongSession(exercise: selectedPlayAlongExercise)
            playAlongPhase = .running
            recordPracticeStart(
                PracticeShortcut(kind: .playAlongExercise, referenceID: selectedPlayAlongExercise.id, title: selectedPlayAlongExercise.title)
            )
            startPlayAlongFixture(exercise: selectedPlayAlongExercise)
            return
        }
        do {
            let started = try await audioEngine.startLiveRecording(
                instrumentId: selectedInstrumentId,
                referencePitchHz: referencePitchHz,
                recordingURL: recordingFileStore.destinationURL()
            )
            guard playAlongStartToken == startToken else {
                if started {
                    audioEngine.discardLiveRecording()
                }
                return
            }
            guard started else {
                lastError = .microphoneDenied
                return
            }
            playAlongSession = PlayAlongSession(exercise: selectedPlayAlongExercise)
            playAlongPhase = .running
            recordPracticeStart(
                PracticeShortcut(kind: .playAlongExercise, referenceID: selectedPlayAlongExercise.id, title: selectedPlayAlongExercise.title)
            )
            if metronomeRunning {
                metronomeOutput.stop()
            }
        } catch {
            guard playAlongStartToken == startToken else { return }
            playAlongPhase = .idle
            playAlongSession = nil
            lastError = .microphoneUnavailable
        }
    }

    func skipPlayAlongNote() {
        guard playAlongPhase == .running, var session = playAlongSession else { return }
        session.skipCurrentNote()
        playAlongSession = session
        if session.isComplete {
            finishPlayAlong(session: session)
        }
    }

    func stopPlayAlong() {
        playAlongStartToken = nil
        audioEngine.cancelPendingLiveStart()
        playAlongPhase = .idle
        playAlongFixtureTask?.cancel()
        playAlongFixtureTask = nil
        playAlongUsesFixture = false
        if audioEngine.recording, audioEngine.activeSource == .live {
            audioEngine.discardLiveRecording()
        }
        playAlongSession = nil
        playAlongGrade = nil
    }

    func resetPlayAlong() {
        playAlongStartToken = nil
        audioEngine.cancelPendingLiveStart()
        playAlongFixtureTask?.cancel()
        playAlongFixtureTask = nil
        playAlongUsesFixture = false
        if playAlongPhase == .running, audioEngine.recording, audioEngine.activeSource == .live {
            audioEngine.discardLiveRecording()
        }
        playAlongPhase = .idle
        playAlongSession = nil
        playAlongGrade = nil
    }

    func clearLocalPracticeData() {
        resetPlayAlong()
        clearLocalPracticeArtifacts()
    }

    func startMetronome() {
        guard !metronomeRunning else { return }
        recordingPlayer.stopAndUnload()
        metronomeRunning = true
        metronomeTick = 0
        metronomeCountInRemaining = metronome.countInBeats
        advanceMetronomeClock()
        scheduleMetronomeTimer()
    }

    func stopMetronome() {
        metronomeRunning = false
        metronomeTimer?.invalidate()
        metronomeTimer = nil
        metronomeCountInRemaining = 0
        metronomeLastPulseWasAccented = false
        metronomeOutput.stop()
    }

    func toggleMetronome() {
        metronomeRunning ? stopMetronome() : startMetronome()
    }

    func adjustTempo(by delta: Int) {
        metronome.bpm = min(300, max(20, metronome.bpm + delta))
    }

    func setTempo(_ bpm: Int) {
        metronome.bpm = min(300, max(20, bpm))
    }

    func tapTempo(now: Date = Date()) {
        tapTempoEvents.append(now)
        tapTempoEvents = tapTempoEvents.suffix(5)
        guard tapTempoEvents.count >= 2 else { return }
        let intervals = zip(tapTempoEvents.dropFirst(), tapTempoEvents).map { current, previous in
            current.timeIntervalSince(previous)
        }.filter { $0 > 0.2 && $0 < 2.4 }
        guard !intervals.isEmpty else { return }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        setTempo(Int((60.0 / average).rounded()))
    }

    func setMeter(beats: Int, unit: Int = 4) {
        metronome.beatsPerMeasure = min(12, max(1, beats))
        metronome.beatUnit = [2, 4, 8, 16].contains(unit) ? unit : 4
    }

    func toggleMetronomeMute() {
        setMetronomeVisualOnly(!metronome.visualOnly)
    }

    func setMetronomeVisualOnly(_ visualOnly: Bool) {
        metronome.visualOnly = visualOnly
        if visualOnly {
            metronome.muted = true
        } else {
            metronome.muted = false
            metronome.volume = max(0.6, metronome.volume)
        }
    }

    func setMetronomeVolume(_ volume: Double) {
        let clamped = min(1, max(0, volume))
        metronome.volume = clamped
        metronome.muted = clamped == 0
        metronome.visualOnly = clamped == 0
    }

    func importSampleScore() {
        guard NativeAudioEngine.testFixturesEnabled else { return }
        let score = scoreImporter.makeSampleScore()
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func importScore(from url: URL) throws {
        let score = try scoreImporter.importScore(from: url)
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func importPhotoScore(data: Data, preferredName: String = "Photo score") throws {
        let score = try scoreImporter.importImageData(data, preferredName: preferredName, sourceKind: .photos)
        scores.insert(score, at: 0)
        activeScoreID = score.id
    }

    func storedScoreFileURL(for score: ImportedScore) -> URL? {
        scoreImporter.storedFileURL(named: score.localFileName)
    }

    func deleteScore(id: ImportedScore.ID) {
        guard let deletedScore = scores.first(where: { $0.id == id }) else { return }
        persistenceWriter.flush()
        persistenceWriteGeneration &+= 1
        let preDeleteSnapshot = makeLocalSnapshot()
        let remainingScores = scores.filter { $0.id != id }
        let nextActiveScoreID = activeScoreID == id ? remainingScores.first?.id : activeScoreID
        let updatedSessions = sessions.map { session in
            var updated = session
            if updated.attachedScoreID == id {
                updated.attachedScoreID = nil
                updated.practiceNotes = updated.practiceNotes
                    .replacingOccurrences(of: "Practiced with \(deletedScore.title).", with: "")
                    .replacingOccurrences(of: "Focus: \(deletedScore.annotation.focusMeasures).", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return updated
        }
        let postDeleteSnapshot = makeLocalSnapshot(
            sessions: updatedSessions,
            scores: remainingScores,
            activeScoreID: nextActiveScoreID
        )

        do {
            try persistenceStore.saveOrThrow(postDeleteSnapshot)
        } catch {
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't save the score deletion, so the score and file were kept. Try again.")
            )
            return
        }

        do {
            try scoreImporter.deleteStoredFile(named: deletedScore.localFileName)
        } catch {
            do {
                try persistenceStore.saveOrThrow(preDeleteSnapshot)
            } catch {
                lastError = .apiRequestFailed(
                    statusCode: 500,
                    message: NativeLocalization.string("BrassTune couldn't remove the local score file or restore its saved state. The score is still open; export your data before closing the app.")
                )
                return
            }
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't remove the local score file, so the score was kept. Try again.")
            )
            return
        }

        isRestoringLocalState = true
        sessions = updatedSessions
        scores = remainingScores
        activeScoreID = nextActiveScoreID
        isRestoringLocalState = false
        lastError = nil
    }

    private func makeLocalSnapshot(
        sessions: [PracticeSession],
        scores: [ImportedScore],
        activeScoreID: ImportedScore.ID?
    ) -> NativeLocalSnapshot {
        NativeLocalSnapshot(
            selectedInstrumentId: selectedInstrumentId,
            referencePitchHz: referencePitchHz,
            sessions: sessions,
            scores: scores,
            activeScoreID: activeScoreID,
            metronome: metronome,
            metronomeDefaultsVersion: 2,
            tutorialCompleted: tutorialCompleted,
            snapshotVersion: 5,
            practiceFeatures: practiceFeatures,
            gatewayCompleted: gatewayCompleted,
            appLanguage: appLanguage,
            successHapticsEnabled: successHapticsEnabled,
            guestProgressSafetyPromptHandled: guestProgressSafetyPromptHandled,
            microphoneRationaleSeen: microphoneRationaleSeen
        )
    }

    private func makeLocalSnapshot() -> NativeLocalSnapshot {
        makeLocalSnapshot(
            sessions: sessions,
            scores: scores,
            activeScoreID: activeScoreID
        )
    }

    func attachScoreToLatestSession(scoreID: ImportedScore.ID) {
        guard !sessions.isEmpty else { return }
        guard let score = scores.first(where: { $0.id == scoreID }) else { return }
        sessions[0].attachedScoreID = score.id
        sessions[0].practiceNotes = "Practiced with \(score.title). \(score.annotation.focusMeasures.isEmpty ? "" : "Focus: \(score.annotation.focusMeasures).")"
        activeScoreID = score.id
    }

    func selectScorePage(scoreID: ImportedScore.ID, pageID: ScorePage.ID) {
        updateScore(scoreID) { score in
            score.selectedPageID = pageID
        }
    }

    func rotateSelectedScorePage(scoreID: ImportedScore.ID) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.rotationDegrees = (page.rotationDegrees + 90) % 360
        }
    }

    func setSelectedScorePageCrop(scoreID: ImportedScore.ID, crop: ScoreCropPreset) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.cropPreset = crop
        }
    }

    func setSelectedScorePageEnhancement(scoreID: ImportedScore.ID, enhancement: ScoreEnhancement) {
        updateSelectedPage(scoreID: scoreID) { page in
            page.enhancement = enhancement
        }
    }

    func updateScoreAnnotation(
        scoreID: ImportedScore.ID,
        focusMeasures: String? = nil,
        notes: String? = nil,
        tempoTarget: Int? = nil,
        problemPassage: String? = nil
    ) {
        updateScore(scoreID) { score in
            if let focusMeasures { score.annotation.focusMeasures = focusMeasures }
            if let notes { score.annotation.notes = notes }
            if let tempoTarget { score.annotation.tempoTarget = min(240, max(30, tempoTarget)) }
            if let problemPassage { score.annotation.problemPassage = problemPassage }
        }
    }

    private func updateScore(_ scoreID: ImportedScore.ID, mutate: (inout ImportedScore) -> Void) {
        guard let index = scores.firstIndex(where: { $0.id == scoreID }) else { return }
        mutate(&scores[index])
    }

    private func updateSelectedPage(scoreID: ImportedScore.ID, mutate: (inout ScorePage) -> Void) {
        updateScore(scoreID) { score in
            let selectedID = score.selectedPageID ?? score.pages.first?.id
            guard let pageIndex = score.pages.firstIndex(where: { $0.id == selectedID }) else { return }
            mutate(&score.pages[pageIndex])
        }
    }

    private func scheduleMetronomeTimer() {
        metronomeTimer?.invalidate()
        guard metronomeRunning else { return }
        // Schedule in .common modes so the beat does not pause while the user
        // scrolls a list (the main run loop switches to .tracking during scroll,
        // and a .default-only timer stops firing there).
        let timer = Timer(timeInterval: metronome.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.metronomeRunning else { return }
                self.advanceMetronomeClock()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        metronomeTimer = timer
    }

    /// One scheduled pulse. Kept separate from Timer plumbing so the
    /// count-in state is deterministic and can be exercised without waiting
    /// on the run loop. Count-in clicks never masquerade as measure accents.
    func advanceMetronomeClock() {
        guard metronomeRunning else { return }
        if metronomeCountInRemaining > 0 {
            metronomeCountInRemaining -= 1
            metronomeLastPulseWasAccented = false
            metronomeOutput.playTick(settings: effectiveMetronomeSettings, accent: false)
            return
        }
        let accent = metronome.accentFirstBeat && metronomeTick == 0
        metronomeLastPulseWasAccented = accent
        metronomeOutput.playTick(settings: effectiveMetronomeSettings, accent: accent)
        metronomeTick = (metronomeTick + 1) % max(1, metronome.beatsPerMeasure * metronome.subdivision.ticksPerBeat)
    }

    private func restartMetronomeIfNeeded() {
        guard metronomeRunning else { return }
        let settings = effectiveMetronomeSettings
        if settings.visualOnly || settings.muted || settings.volume <= 0 {
            metronomeOutput.stop()
        }
        scheduleMetronomeTimer()
    }

    private var effectiveMetronomeSettings: MetronomeSettings {
        guard metronomeTemporarilyMutedForRecording else { return metronome }
        var mutedSettings = metronome
        mutedSettings.muted = true
        mutedSettings.visualOnly = true
        mutedSettings.volume = 0
        return mutedSettings
    }

    private func observeAudioFrames() {
        audioFrameCancellable = audioEngine.$currentFrame
            .compactMap { $0 }
            .sink { [weak self] frame in
                Task { @MainActor [weak self] in
                    self?.consumePlayAlongFrame(frame)
                }
            }
        audioRecordingCancellable = audioEngine.$recording
            .removeDuplicates()
            .sink { [weak self] isRecording in
                Task { @MainActor [weak self] in
                    guard let self,
                          !isRecording,
                          self.playAlongPhase == .running,
                          !self.playAlongUsesFixture else { return }
                    self.playAlongStartToken = nil
                    self.playAlongSession = nil
                    self.playAlongGrade = nil
                    self.playAlongPhase = .idle
                    self.lastError = .microphoneUnavailable
                }
            }
    }

    private func consumePlayAlongFrame(_ frame: PitchFrame) {
        guard playAlongPhase == .running, var session = playAlongSession else { return }
        session.feed(frame)
        playAlongSession = session
        if session.isComplete {
            finishPlayAlong(session: session)
        }
    }

    private func startPlayAlongFixture(exercise: PlayAlongExercise) {
        playAlongFixtureTask?.cancel()
        playAlongUsesFixture = true
        playAlongFixtureTask = Task { [weak self] in
            for (noteIndex, note) in exercise.writtenNotes.enumerated() {
                // Preserve the production two-second confirmed-hold contract in
                // fixture timestamps while accelerating wall-clock UI-test time.
                for frameIndex in 0...20 {
                    guard !Task.isCancelled else { return }
                    let frame = PitchFrame(
                        timestampMs: noteIndex * 2_500 + frameIndex * 100,
                        frequencyHz: 440,
                        confidence: 0.98,
                        rms: 0.08,
                        centsDeviation: 0,
                        tuningStatus: .inTune,
                        writtenNoteName: note,
                        writtenOctave: 4,
                        isValidForRecording: true
                    )
                    self?.consumePlayAlongFrame(frame)
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }

    private func finishPlayAlong(session: PlayAlongSession) {
        guard playAlongPhase == .running, session.isComplete else { return }
        playAlongSession = session
        playAlongGrade = session.grade
        if let grade = session.grade {
            practiceFeatures.playAlongAttempts.insert(
                PlayAlongAttemptSummary(exercise: session.exercise, noteGrades: grade.noteGrades),
                at: 0
            )
            practiceFeatures.playAlongAttempts = Array(practiceFeatures.playAlongAttempts.prefix(200))
        }
        // Complete the state transition before stopping capture because the
        // engine republishes its last real frame as it closes.
        playAlongPhase = .completed
        if playAlongUsesFixture {
            playAlongFixtureTask?.cancel()
            playAlongFixtureTask = nil
            playAlongUsesFixture = false
            return
        }
        let capture = audioEngine.stopLiveRecording()
        if !capture.frames.isEmpty || capture.recordingURL != nil {
            _ = saveRecordedSession(
                capture: capture,
                source: .live,
                preferredName: session.exercise.title,
                practiceNotes: NativeLocalization.format(
                    "Play-Along: %@.",
                    session.exercise.title
                )
            )
        }
    }

    @discardableResult
    private func saveRecordedSession(
        frames: [PitchFrame],
        source: PracticeSessionSource,
        preferredName: String? = nil,
        practiceNotes: String? = nil,
        retainedRecordingURL: URL? = nil,
        startedAt explicitStartedAt: Date? = nil,
        endedAt explicitEndedAt: Date? = nil
    ) -> Bool {
        guard !frames.isEmpty else {
            lastError = .microphoneUnavailable
            return false
        }
        let endedAt = explicitEndedAt ?? Date()
        let duration = source == .live ? Double(max(1, (frames.last?.timestampMs ?? 0) - (frames.first?.timestampMs ?? 0))) / 1000.0 : Double(frames.count) * 0.11
        let startedAt = explicitStartedAt ?? endedAt.addingTimeInterval(-duration)
        let matchingSourceCount = sessions.filter { $0.source == source }.count + 1
        let session = PracticeSession(
            id: UUID(),
            name: preferredName ?? (matchingSourceCount == 1 ? source.sessionTitle : "\(source.sessionTitle) \(matchingSourceCount)"),
            instrumentId: selectedInstrumentId,
            startedAt: startedAt,
            endedAt: endedAt,
            frames: frames,
            retainedRecordingURL: retainedRecordingURL,
            attachedScoreID: activeScore?.id,
            practiceNotes: practiceNotes ?? activeScore.map { "Practiced with \($0.title)." } ?? "",
            source: source
        )
        sessions.insert(session, at: 0)
        return true
    }

    @discardableResult
    private func saveRecordedSession(
        capture: NativeLiveCapture,
        source: PracticeSessionSource,
        preferredName: String? = nil,
        practiceNotes: String? = nil
    ) -> Bool {
        let availableRecordingURL = recordingFileStore.availableURL(capture.recordingURL)
        if capture.recordingURL != nil, availableRecordingURL == nil {
            try? recordingFileStore.deleteRecording(at: capture.recordingURL)
        }
        if let retentionFailure = capture.recordingRetentionFailure,
           availableRecordingURL != nil,
           retentionFailure != .writeFailed {
            // A quota ends only audio retention. The capped CAF remains
            // playable and the complete pitch result is still saved.
            lastError = nil
            audioEngine.setExternalAudioNotice(Self.partialRecordingNotice())
        } else if capture.recordingRetentionFailure != nil {
            let message = NativeLocalization.string(
                "BrassTune couldn't save your latest changes on this device. Keep the app open, export your data if needed, and try again."
            )
            lastError = .apiRequestFailed(statusCode: 500, message: message)
            audioEngine.setExternalAudioNotice(message)
        }
        guard !capture.frames.isEmpty || availableRecordingURL != nil else {
            lastError = .microphoneUnavailable
            return false
        }
        let matchingSourceCount = sessions.filter { $0.source == source }.count + 1
        let session = PracticeSession(
            id: UUID(),
            name: preferredName ?? (matchingSourceCount == 1 ? source.sessionTitle : "\(source.sessionTitle) \(matchingSourceCount)"),
            instrumentId: selectedInstrumentId,
            startedAt: capture.startedAt,
            endedAt: capture.endedAt,
            frames: capture.frames,
            retainedRecordingURL: availableRecordingURL,
            attachedScoreID: activeScore?.id,
            practiceNotes: practiceNotes ?? activeScore.map { "Practiced with \($0.title)." } ?? "",
            source: source
        )
        sessions.insert(session, at: 0)
        return true
    }

    @discardableResult
    func retainUnexpectedLiveCapture(_ capture: NativeLiveCapture) -> Bool {
        guard capture.completionReason != .userStopped,
              retainedUnexpectedCaptureIDs.insert(capture.id).inserted else {
            return false
        }

        let interruptedPlayAlong = playAlongPhase == .running ? playAlongSession : nil
        playAlongStartToken = nil
        playAlongFixtureTask?.cancel()
        playAlongFixtureTask = nil
        playAlongUsesFixture = false
        playAlongPhase = .idle
        playAlongSession = nil
        playAlongGrade = nil

        let preferredName = interruptedPlayAlong?.exercise.title
        let practiceNotes = interruptedPlayAlong.map {
            NativeLocalization.format("Play-Along: %@.", $0.exercise.title)
        }
        let saved = saveRecordedSession(
            capture: capture,
            source: .live,
            preferredName: preferredName,
            practiceNotes: practiceNotes
        )
        let savedMessage: String
        switch capture.completionReason {
        case .interruption:
            savedMessage = NativeLocalization.string("Recording stopped because the audio session was interrupted.")
                + (saved ? " \(NativeLocalization.string("Saved"))" : "")
        case .routeLoss:
            savedMessage = NativeLocalization.string("Your audio output changed. Check your headphones or speaker before continuing.")
                + (saved ? " \(NativeLocalization.string("Saved"))" : "")
        case .userStopped:
            savedMessage = ""
        }
        if let retentionFailure = capture.recordingRetentionFailure,
           retentionFailure != .writeFailed,
           saved,
           sessions.first?.retainedRecordingURL != nil {
            // A quota preserves a playable capped CAF; only the audio is
            // partial while the tuning result covers the complete session.
            audioEngine.setExternalAudioNotice(Self.partialRecordingNotice())
        } else if capture.recordingRetentionFailure != nil {
            audioEngine.setExternalAudioNotice(lastError?.localizedDescription)
        } else {
            audioEngine.setExternalAudioNotice(savedMessage)
        }
        return saved
    }

    private func prepareForRecordingPlayback() {
        cancelRecordingStart()
        if playAlongPhase == .running || playAlongStartInProgress {
            stopPlayAlong()
        } else if audioEngine.recording {
            stopRecording()
        }
        stopMetronome()
        audioEngine.stopTone()
    }

    private static func partialRecordingNotice() -> String {
        NativeLocalization.string(
            "The recording reached its local limit. Saved audio is partial; tuning results include the full session."
        )
    }

    @discardableResult
    private func clearLocalPracticeArtifacts() -> Bool {
        recordingPlayer.stopAndUnload()
        persistenceWriter.flush()
        persistenceWriteGeneration &+= 1
        let snapshot = makeLocalSnapshot()
        do {
            try persistenceStore.clear()
        } catch {
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't clear its saved local data, so your practice data was kept. Try again.")
            )
            return false
        }

        do {
            // Remove recordings before score files. If the recording directory
            // cannot be removed, no other local artifacts have been touched and
            // restoring this snapshot is a true all-or-nothing rollback.
            try recordingFileStore.deleteAllStoredFiles()
        } catch {
            do {
                try persistenceStore.saveOrThrow(snapshot)
            } catch {
                lastError = .apiRequestFailed(
                    statusCode: 500,
                    message: NativeLocalization.string("BrassTune couldn't finish clearing local data or restore its saved copy. Your data is still open; export it before closing the app.")
                )
                return false
            }
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't clear its saved local data, so your practice data was kept. Try again.")
            )
            return false
        }

        do {
            try scoreImporter.deleteAllStoredFiles()
        } catch {
            // Recording deletion succeeded, so this cannot be a fully atomic
            // rollback. Preserve the persisted snapshot and leave the visible
            // model untouched rather than reporting a successful clear.
            do {
                try persistenceStore.saveOrThrow(snapshot)
            } catch {
                lastError = .apiRequestFailed(
                    statusCode: 500,
                    message: NativeLocalization.string("BrassTune couldn't finish clearing local data or restore its saved copy. Your data is still open; export it before closing the app.")
                )
                return false
            }
            lastError = .apiRequestFailed(
                statusCode: 500,
                message: NativeLocalization.string("BrassTune couldn't remove your imported score files, so your local practice data was kept. Try again.")
            )
            return false
        }

        isRestoringLocalState = true
        sessions.removeAll()
        scores.removeAll()
        activeScoreID = nil
        practiceFeatures = Self.freshPracticeFeatureState()
        persistedSessionIDs = []
        guestProgressSafetyPromptEligible = false
        isRestoringLocalState = false
        return true
    }

    private func restoreLocalData() throws {
        guard let snapshot = try persistenceStore.load() else { return }
        let needsMetronomeDefaultMigration = (snapshot.metronomeDefaultsVersion ?? 1) < 2
            && snapshot.metronome.muted
            && snapshot.metronome.visualOnly
            && snapshot.metronome.volume == 0
        isRestoringLocalState = true
        selectedInstrumentId = snapshot.selectedInstrumentId
        referencePitchHz = snapshot.referencePitchHz
        let restoredSessions = NativeAudioEngine.testFixturesEnabled
            ? snapshot.sessions
            : snapshot.sessions.filter { $0.source == .live }
        sessions = restoredSessions.map { storedSession in
            var migrated = storedSession
            migrated.retainedRecordingURL = recordingFileStore.availableURL(storedSession.retainedRecordingURL)
            return migrated
        }
        scores = NativeAudioEngine.testFixturesEnabled
            ? snapshot.scores
            : snapshot.scores.filter { $0.sourceKind != .sample }
        activeScoreID = scores.contains(where: { $0.id == snapshot.activeScoreID })
            ? snapshot.activeScoreID
            : scores.first?.id
        metronome = needsMetronomeDefaultMigration ? MetronomeSettings() : snapshot.metronome
        tutorialCompleted = snapshot.tutorialCompleted ?? false
        gatewayCompleted = snapshot.gatewayCompleted ?? (snapshot.tutorialCompleted ?? false)
        appLanguage = snapshot.appLanguage ?? .system
        var restoredFeatures = snapshot.practiceFeatures ?? Self.freshPracticeFeatureState()
        // Persisted checkpoints are resumable navigation state, never proof
        // that audio or a clock is still running after process restoration.
        restoredFeatures.warmupCheckpoint?.runningSince = nil
        restoredFeatures.workspaceCheckpoint?.blockRunningSince = nil
        practiceFeatures = restoredFeatures
        successHapticsEnabled = snapshot.successHapticsEnabled ?? true
        guestProgressSafetyPromptHandled = snapshot.guestProgressSafetyPromptHandled ?? false
        microphoneRationaleSeen = snapshot.microphoneRationaleSeen ?? false
        guestProgressSafetyPromptEligible = false
        persistedSessionIDs = Set(sessions.map(\.id))
        isRestoringLocalState = false
        let removedFixtures = sessions.count != snapshot.sessions.count || scores.count != snapshot.scores.count
        if needsMetronomeDefaultMigration || removedFixtures || snapshot.metronomeDefaultsVersion != 2 {
            persistLocalData()
        }
    }

    private func persistLocalData() {
        guard !isRestoringLocalState, persistenceAccessState.canPersist else { return }
        persistenceWriteGeneration &+= 1
        let generation = persistenceWriteGeneration
        let snapshot = makeLocalSnapshot()
        let store = persistenceStore
        persistenceWriter.save(
            generation: generation,
            snapshot: snapshot,
            store: store
        ) { [weak self] completedGeneration, result in
            self?.handlePersistenceCompletion(
                generation: completedGeneration,
                snapshot: snapshot,
                result: result
            )
        }
    }

    private func handlePersistenceCompletion(
        generation: Int,
        snapshot: NativeLocalSnapshot,
        result: Result<Void, Error>
    ) {
        guard generation == persistenceWriteGeneration else { return }
        switch result {
        case .success:
            persistenceErrorMessage = nil
            let snapshotSessionIDs = Set(snapshot.sessions.map(\.id))
            let newlyPersistedSessionIDs = snapshotSessionIDs.subtracting(persistedSessionIDs)
            persistedSessionIDs = snapshotSessionIDs
            guard !newlyPersistedSessionIDs.isEmpty else { return }
            persistedPracticeSuccessSequence &+= 1
            if activeStorageNamespace == .guest,
               !guestProgressSafetyPromptHandled {
                guestProgressSafetyPromptEligible = true
            }
        case .failure:
            persistenceErrorMessage = NativeLocalization.string("BrassTune couldn't save your latest changes on this device. Keep the app open, export your data if needed, and try again.")
        }
    }

    @discardableResult
    private func prepareStorageNamespace(_ namespace: NativeStorageNamespace) -> Bool {
        persistenceWriter.flush()
        persistenceWriteGeneration &+= 1
        persistenceAccessState = .restoringIdentity
        recordingPlayer.stopAndUnload()
        stopFeatureAudio()
        isRestoringLocalState = true
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440
        sessions = []
        scores = []
        activeScoreID = nil
        metronome = MetronomeSettings()
        practiceFeatures = Self.freshPracticeFeatureState()
        successHapticsEnabled = true
        guestProgressSafetyPromptHandled = false
        microphoneRationaleSeen = false
        guestProgressSafetyPromptEligible = false
        persistedSessionIDs = []
        gatewayCompleted = namespace != .guest
        tutorialCompleted = false
        appLanguage = .system
        isRestoringLocalState = false

        activeStorageNamespace = namespace
        persistenceStore = guestPersistenceStore.scoped(to: namespace)
        scoreImporter = NativeScoreImportService(
            storageDirectory: namespace.scoreDirectory(basedAt: guestScoreStorageDirectory),
            removeItem: scoreFileRemover
        )
        recordingFileStore = NativeRecordingFileStore(
            storageDirectory: namespace.recordingDirectory(basedAt: guestRecordingStorageDirectory),
            removeItem: recordingFileRemover
        )
        do {
            try restoreLocalData()
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceAccessState = .lockedSignedOut
            gatewayCompleted = false
            persistenceErrorMessage = NativeLocalization.string("BrassTune couldn't read its saved practice data. Your existing data was kept; restart the app or contact support before continuing.")
            return false
        }
    }

    @discardableResult
    private func activateStorageNamespace(_ namespace: NativeStorageNamespace) -> Bool {
        retryPendingAccountPurges()
        if activeStorageNamespace != namespace || !persistenceAccessState.matches(namespace) {
            guard prepareStorageNamespace(namespace) else { return false }
        }
        persistenceAccessState = namespace.accessState
        return true
    }

    private func transitionToUnauthenticated(_ state: AuthState) {
        persistenceWriter.flush()
        persistenceWriteGeneration &+= 1
        persistenceAccessState = .lockedSignedOut
        recordingPlayer.stopAndUnload()
        stopFeatureAudio()
        isRestoringLocalState = true
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440
        sessions = []
        scores = []
        activeScoreID = nil
        metronome = MetronomeSettings()
        practiceFeatures = Self.freshPracticeFeatureState()
        successHapticsEnabled = true
        guestProgressSafetyPromptHandled = false
        microphoneRationaleSeen = false
        guestProgressSafetyPromptEligible = false
        persistedSessionIDs = []
        pendingDestination = nil
        gatewayCompleted = false
        tutorialCompleted = false
        appLanguage = .system
        ensembles = []
        selectedEnsembleID = nil
        ensembleInvitations = []
        selectedEnsembleDetail = nil
        selectedEnsembleRoster = []
        selectedEnsembleAggregate = nil
        ensembleStatusMessage = nil
        isRestoringLocalState = false
        authState = state
    }
}

private struct BackendDeletionResponse: Decodable {
    let deleted: Bool
    let deletionStatus: String?

    enum CodingKeys: String, CodingKey {
        case deleted
        case deletionStatus = "deletion_status"
    }
}

private struct EnsembleJoinResponse: Decodable {
    let joined: Bool
    let groupID: Int
    let groupName: String

    enum CodingKeys: String, CodingKey {
        case joined
        case groupID = "group_id"
        case groupName = "group_name"
    }
}

private struct EnsembleLeaveResponse: Decodable {
    let left: Bool
    let groupID: Int

    enum CodingKeys: String, CodingKey {
        case left
        case groupID = "group_id"
    }
}

enum NativeStorageNamespace: Equatable {
    case guest
    case account(userID: String)

    var accountDigest: String? {
        guard case .account(let userID) = self else { return nil }
        let digest = SHA256.hash(data: Data(userID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func scoreDirectory(basedAt guestDirectory: URL) -> URL {
        guard let accountDigest else { return guestDirectory }
        return Self.scoreDirectory(accountDigest: accountDigest, basedAt: guestDirectory)
    }

    func recordingDirectory(basedAt guestDirectory: URL) -> URL {
        guard let accountDigest else { return guestDirectory }
        return Self.recordingDirectory(accountDigest: accountDigest, basedAt: guestDirectory)
    }

    func stateFile(basedAt guestFile: URL) -> URL {
        guard let accountDigest else { return guestFile }
        return Self.stateFile(accountDigest: accountDigest, basedAt: guestFile)
    }

    static func scoreDirectory(accountDigest: String, basedAt guestDirectory: URL) -> URL {
        guestDirectory.appendingPathComponent("Account-\(accountDigest)", isDirectory: true)
    }

    static func recordingDirectory(accountDigest: String, basedAt guestDirectory: URL) -> URL {
        guestDirectory.appendingPathComponent("Account-\(accountDigest)", isDirectory: true)
    }

    static func stateFile(accountDigest: String, basedAt guestFile: URL) -> URL {
        let base = guestFile.deletingPathExtension().lastPathComponent
        let ext = guestFile.pathExtension
        let name = "\(base)-account-\(accountDigest)" + (ext.isEmpty ? "" : ".\(ext)")
        return guestFile.deletingLastPathComponent().appendingPathComponent(name)
    }
}

struct PendingDigestStore {
    private let load: () -> [String]
    private let save: ([String]) -> Void

    init(load: @escaping () -> [String], save: @escaping ([String]) -> Void) {
        self.load = load
        self.save = save
    }

    static func live(defaults: UserDefaults = .standard, key: String) -> PendingDigestStore {
        PendingDigestStore(
            load: { defaults.stringArray(forKey: key) ?? [] },
            save: { defaults.set($0, forKey: key) }
        )
    }

    var pendingDigests: [String] {
        load().filter { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }
    }

    func enqueue(_ digest: String) {
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { return }
        save(Array(Set(pendingDigests + [digest])).sorted())
    }

    func remove(_ digest: String) {
        save(pendingDigests.filter { $0 != digest })
    }
}

enum PersistenceAccessState: Equatable {
    case restoringIdentity
    case lockedSignedOut
    case guest
    case account(userID: String)

    var canPersist: Bool {
        switch self {
        case .guest, .account: return true
        case .restoringIdentity, .lockedSignedOut: return false
        }
    }

    func matches(_ namespace: NativeStorageNamespace) -> Bool {
        switch (self, namespace) {
        case (.guest, .guest): return true
        case (.account(let lhs), .account(let rhs)): return lhs == rhs
        default: return false
        }
    }
}

private extension NativeStorageNamespace {
    var accessState: PersistenceAccessState {
        switch self {
        case .guest: return .guest
        case .account(let userID): return .account(userID: userID)
        }
    }
}

struct NativePersistenceStore: @unchecked Sendable {
    let fileURL: URL
    private let removeItem: (URL) throws -> Void
    private let writeData: (Data, URL) throws -> Void

    init(
        fileURL: URL,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic])
        }
    ) {
        self.fileURL = fileURL
        self.removeItem = removeItem
        self.writeData = writeData
    }

    static func live() -> NativePersistenceStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrassTune", isDirectory: true)
        return NativePersistenceStore(fileURL: directory.appendingPathComponent("native-local-state.json"))
    }

    static func ephemeral(
        fileURL: URL,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic])
        }
    ) -> NativePersistenceStore {
        NativePersistenceStore(fileURL: fileURL, removeItem: removeItem, writeData: writeData)
    }

    func scoped(to namespace: NativeStorageNamespace) -> NativePersistenceStore {
        NativePersistenceStore(
            fileURL: namespace.stateFile(basedAt: fileURL),
            removeItem: removeItem,
            writeData: writeData
        )
    }

    func scoped(accountDigest: String) -> NativePersistenceStore {
        NativePersistenceStore(
            fileURL: NativeStorageNamespace.stateFile(accountDigest: accountDigest, basedAt: fileURL),
            removeItem: removeItem,
            writeData: writeData
        )
    }

    func load() throws -> NativeLocalSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NativeLocalSnapshot.self, from: data)
    }

    func save(_ snapshot: NativeLocalSnapshot) {
        do {
            try saveOrThrow(snapshot)
        } catch {
            // Local persistence failures should not block practice in the beta app.
        }
    }

    func saveOrThrow(_ snapshot: NativeLocalSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try writeData(data, fileURL)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try removeItem(fileURL)
    }
}

struct NativeLocalSnapshot: Codable, Equatable {
    var selectedInstrumentId: String
    var referencePitchHz: Double
    var sessions: [PracticeSession]
    var scores: [ImportedScore]
    var activeScoreID: ImportedScore.ID?
    var metronome: MetronomeSettings
    var metronomeDefaultsVersion: Int? = nil
    var tutorialCompleted: Bool? = nil
    var snapshotVersion: Int? = nil
    var practiceFeatures: PracticeFeatureState? = nil
    var gatewayCompleted: Bool? = nil
    var appLanguage: AppLanguage? = nil
    var successHapticsEnabled: Bool? = nil
    var guestProgressSafetyPromptHandled: Bool? = nil
    var microphoneRationaleSeen: Bool? = nil
}

struct NativeScoreImportService {
    enum ImportError: LocalizedError, Equatable {
        case unsupportedType
        case unreadableFile
        case fileTooLarge
        case noPages
        case tooManyPages(maximum: Int)
        case cleanupFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedType: return NativeLocalization.string("BrassTune can import PDF, JPEG, PNG, and HEIC score files.")
            case .unreadableFile: return NativeLocalization.string("BrassTune could not read that score file.")
            case .fileTooLarge: return NativeLocalization.string("This file is too large to import.")
            case .noPages: return NativeLocalization.string("No score pages were found in that file.")
            case .tooManyPages(let maximum): return NativeLocalization.format(
                "This PDF has more than %@ pages. Split it into smaller files before importing.",
                String(maximum)
            )
            case .cleanupFailed: return NativeLocalization.string("The score could not be imported, and BrassTune could not remove its copied file. The copied file remains on this device.")
            }
        }
    }

    static let defaultStorageDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BrassTune/ImportedScores", isDirectory: true)

    let storageDirectory: URL
    private let removeItem: (URL) throws -> Void
    private let maxFileSizeBytes: Int64 = 30 * 1024 * 1024
    private let maxPages = 32

    init(
        storageDirectory: URL,
        removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.storageDirectory = storageDirectory
        self.removeItem = removeItem
    }

    func importScore(from url: URL) throws -> ImportedScore {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize <= maxFileSizeBytes else { throw ImportError.fileTooLarge }

        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let sourceKind: ScoreSourceKind
        if type?.conforms(to: .pdf) == true {
            sourceKind = .filesPDF
        } else if type?.conforms(to: .image) == true || ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) {
            sourceKind = .filesImage
        } else {
            throw ImportError.unsupportedType
        }

        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "score" : url.pathExtension)"
        let storedURL = storageDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: storedURL.path) {
            try removeItem(storedURL)
        }
        try FileManager.default.copyItem(at: url, to: storedURL)

        do {
            switch sourceKind {
            case .filesPDF:
                return try makePDFScore(from: storedURL, localFileName: fileName, fileSize: fileSize)
            case .filesImage:
                return try makeImageScore(from: storedURL, localFileName: fileName, fileSize: fileSize, sourceKind: .filesImage)
            case .photos, .sample:
                throw ImportError.unsupportedType
            }
        } catch let importError {
            do {
                try deleteStoredFile(named: fileName)
            } catch {
                throw ImportError.cleanupFailed
            }
            throw importError
        }
    }

    func importImageData(_ data: Data, preferredName: String, sourceKind: ScoreSourceKind) throws -> ImportedScore {
        guard data.count <= maxFileSizeBytes else { throw ImportError.fileTooLarge }
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).png"
        let storedURL = storageDirectory.appendingPathComponent(fileName)
        try data.write(to: storedURL, options: [.atomic])
        do {
            var score = try makeImageScore(from: storedURL, localFileName: fileName, fileSize: Int64(data.count), sourceKind: sourceKind)
            score.title = preferredName
            return score
        } catch let importError {
            do {
                try deleteStoredFile(named: fileName)
            } catch {
                throw ImportError.cleanupFailed
            }
            throw importError
        }
    }

    func makeSampleScore() -> ImportedScore {
        let pages = (1...3).map { index in
            ScorePage(
                id: UUID(),
                pageNumber: index,
                titleSuggestion: index == 1 ? "Long-tone study" : nil,
                textSuggestions: index == 1 ? ["Long-tone study", "Quarter note = 92", "Phrase A"] : ["Phrase \(index)"],
                thumbnailPNGData: makeSyntheticThumbnail(page: index),
                suggestedRegions: [
                    ScoreRegion(id: UUID(), label: "Phrase \(index)", normalizedX: 0.12, normalizedY: 0.20, normalizedWidth: 0.76, normalizedHeight: 0.18),
                    ScoreRegion(id: UUID(), label: "Problem passage", normalizedX: 0.18, normalizedY: 0.52, normalizedWidth: 0.66, normalizedHeight: 0.16),
                ]
            )
        }
        return ImportedScore(
            id: UUID(),
            title: "Long-tone study",
            composer: "BrassTune sample",
            sourceKind: .sample,
            localFileName: nil,
            importedAt: Date(),
            pages: pages,
            selectedPageID: pages.first?.id,
            annotation: ScoreAnnotation(focusMeasures: "1-8", notes: "Start with steady air before adding metronome.", tempoTarget: 92, problemPassage: "Opening attacks"),
            originalFileSizeBytes: 0
        )
    }

    func deleteStoredFile(named fileName: String?) throws {
        guard let fileName else { return }
        let url = storageDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try removeItem(url)
    }

    func storedFileURL(named fileName: String?) -> URL? {
        guard let fileName else { return nil }
        let url = storageDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteAllStoredFiles() throws {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else { return }
        try removeItem(storageDirectory)
    }

    private func makePDFScore(from url: URL, localFileName: String, fileSize: Int64) throws -> ImportedScore {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadableFile }
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ImportError.noPages }
        guard pageCount <= maxPages else { throw ImportError.tooManyPages(maximum: maxPages) }
        let pages: [ScorePage] = (0..<pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let text = page.string ?? ""
            let suggestions = metadataLines(from: text)
            let thumbnail = page.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
            return ScorePage(
                id: UUID(),
                pageNumber: index + 1,
                titleSuggestion: suggestions.first,
                textSuggestions: suggestions,
                thumbnailPNGData: thumbnail.pngData(),
                suggestedRegions: suggestedScoreRegions(pageNumber: index + 1)
            )
        }
        guard !pages.isEmpty else { throw ImportError.noPages }
        return ImportedScore(
            id: UUID(),
            title: pages.first?.titleSuggestion ?? url.deletingPathExtension().lastPathComponent,
            composer: composerSuggestion(from: pages.flatMap(\.textSuggestions)),
            sourceKind: .filesPDF,
            localFileName: localFileName,
            importedAt: Date(),
            pages: pages,
            selectedPageID: pages.first?.id,
            originalFileSizeBytes: fileSize
        )
    }

    private func makeImageScore(from url: URL, localFileName: String, fileSize: Int64, sourceKind: ScoreSourceKind) throws -> ImportedScore {
        // Decode the image through ImageIO downsampling so a high-megapixel photo
        // never gets fully expanded into an uncompressed bitmap in memory (which
        // can trip jetsam on device even under the file-size gate). The original
        // file on disk stays untouched; only the in-memory image is capped.
        guard let image = downsampledImage(at: url, maxPixelSize: 2400) else { throw ImportError.unreadableFile }
        let thumbnail = downsampledPNG(image: image)
        let page = ScorePage(
            id: UUID(),
            pageNumber: 1,
            titleSuggestion: url.deletingPathExtension().lastPathComponent,
            textSuggestions: ["Image import", "Review title/composer manually"],
            thumbnailPNGData: thumbnail,
            suggestedRegions: suggestedScoreRegions(pageNumber: 1)
        )
        return ImportedScore(
            id: UUID(),
            title: url.deletingPathExtension().lastPathComponent,
            composer: nil,
            sourceKind: sourceKind,
            localFileName: localFileName,
            importedAt: Date(),
            pages: [page],
            selectedPageID: page.id,
            originalFileSizeBytes: fileSize
        )
    }

    private func metadataLines(from text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(5))
    }

    private func composerSuggestion(from lines: [String]) -> String? {
        lines.first { line in
            let lowercased = line.lowercased()
            return lowercased.contains("arr.") || lowercased.contains("composer") || lowercased.contains("by ")
        }
    }

    private func suggestedScoreRegions(pageNumber: Int) -> [ScoreRegion] {
        [
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).1", normalizedX: 0.10, normalizedY: 0.18, normalizedWidth: 0.80, normalizedHeight: 0.18),
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).2", normalizedX: 0.10, normalizedY: 0.44, normalizedWidth: 0.80, normalizedHeight: 0.18),
            ScoreRegion(id: UUID(), label: "Staff group \(pageNumber).3", normalizedX: 0.10, normalizedY: 0.70, normalizedWidth: 0.80, normalizedHeight: 0.18),
        ]
    }

    private func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func downsampledPNG(image: UIImage) -> Data? {
        let maxLength: CGFloat = 320
        let scale = min(1, maxLength / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.pngData()
    }

    private func makeSyntheticThumbnail(page: Int) -> Data? {
        let size = CGSize(width: 220, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.94, green: 0.79, blue: 0.44, alpha: 1).setStroke()
            for system in 0..<3 {
                let top = 42 + system * 72
                for line in 0..<5 {
                    let y = CGFloat(top + line * 7)
                    context.cgContext.move(to: CGPoint(x: 28, y: y))
                    context.cgContext.addLine(to: CGPoint(x: 192, y: y))
                }
            }
            context.cgContext.setLineWidth(1.2)
            context.cgContext.strokePath()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor(red: 0.94, green: 0.79, blue: 0.44, alpha: 1),
            ]
            "p.\(page)".draw(at: CGPoint(x: 82, y: 250), withAttributes: attributes)
        }
        return image.pngData()
    }
}
