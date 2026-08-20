import ImageIO
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
#if PHYSICAL_RELEASE
import AVKit
#endif

enum AppTab: String, CaseIterable, Identifiable {
    case practice
    case tuner
    case scales
    case progress
    case more

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .practice: return "Practice"
        case .tuner: return "Tuner"
        case .scales: return "Scales"
        case .progress: return "Progress"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .practice: return "sun.max"
        case .tuner: return "tuningfork"
        case .scales: return "music.note.list"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .more: return "ellipsis.circle"
        }
    }
}

@MainActor
enum AppSceneAudioLifecycle {
    static func handleTransition(
        from previousPhase: ScenePhase,
        to currentPhase: ScenePhase,
        preservePendingTunerStartWhileInactive: () -> Bool,
        cancelTunerStart: () -> Void,
        isTunerRecording: () -> Bool,
        stopTunerRecording: () -> Void,
        releasePracticeAudio: () -> Void
    ) {
        guard previousPhase == .active, currentPhase != .active else { return }

        // System permission sheets temporarily make the scene inactive while
        // the app is still foregrounded. Let the in-flight microphone request
        // resolve so its real granted/denied state is published; a transition
        // to background still cancels the request unconditionally.
        if currentPhase != .inactive || !preservePendingTunerStartWhileInactive() {
            cancelTunerStart()
        }
        if isTunerRecording() {
            stopTunerRecording()
        }
        releasePracticeAudio()
    }
}

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: AppTab = .practice
    @State private var practicePath = NavigationPath()
    @State private var practiceNavigationGeneration = UUID()
    @State private var onboardingPresented: Bool
    @State private var guestAccountPromptMode: GatewayAuthMode?
    private let resetUITestState: Bool
    private let forceAuthGatewayLaunch: Bool
    private let settingsOnlyLaunch: Bool
    private let uiTestMode: Bool

#if PHYSICAL_RELEASE
    private var physicalRoutePickerTestMode: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_PHYSICAL_ROUTE_PICKER")
    }
#endif

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        settingsOnlyLaunch = arguments.contains("UITEST_SETTINGS")
        resetUITestState = arguments.contains("UITEST_RESET_STATE")
        forceAuthGatewayLaunch = AuthService.allowsUITestAuthOverrides(
            bundleIdentifier: Bundle.main.bundleIdentifier
        ) && arguments.contains("UITEST_FORCE_AUTH_GATEWAY")
        uiTestMode = arguments.contains("UITEST_DEMO")
            || arguments.contains("UITEST_FIXTURES")
            || arguments.contains("UITEST_SETTINGS")
        _onboardingPresented = State(initialValue: false)
        _guestAccountPromptMode = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if model.persistenceAccessState == .restoringIdentity {
                ProgressView("Restoring secure practice data…")
                    .accessibilityIdentifier("app.persistenceLocked")
            } else if settingsOnlyLaunch {
                if onboardingPresented {
                    OnboardingView(isPresented: $onboardingPresented, selectedTab: $selectedTab)
                } else {
                    NavigationStack {
                        SettingsView(onboardingPresented: $onboardingPresented)
                    }
                }
            } else if forceAuthGatewayLaunch || !model.gatewayCompleted {
                AuthGatewayView()
            } else if onboardingPresented {
                OnboardingView(isPresented: $onboardingPresented, selectedTab: $selectedTab)
            } else {
                TabView(selection: $selectedTab) {
                    practiceNavigation(path: $practicePath) {
                        PracticeHomeView(selectedTab: $selectedTab)
                    }
                    .id(practiceNavigationGeneration)
                    .tabItem {
                        Label(AppTab.practice.title, systemImage: AppTab.practice.systemImage)
                    }
                    .tag(AppTab.practice)

                    practiceNavigation {
                        TunerView()
                    }
                    .tabItem {
                        Label(AppTab.tuner.title, systemImage: AppTab.tuner.systemImage)
                    }
                    .tag(AppTab.tuner)

                    practiceNavigation {
                        ScalesTabView()
                    }
                    .tabItem {
                        Label(AppTab.scales.title, systemImage: AppTab.scales.systemImage)
                    }
                    .tag(AppTab.scales)

                    practiceNavigation {
                        ProgressTabView(selectedTab: $selectedTab)
                    }
                    .tabItem {
                        Label(AppTab.progress.title, systemImage: AppTab.progress.systemImage)
                    }
                    .tag(AppTab.progress)

                    practiceNavigation {
                        MoreView(onboardingPresented: $onboardingPresented)
                    }
                    .tabItem {
                        Label(AppTab.more.title, systemImage: AppTab.more.systemImage)
                    }
                    .tag(AppTab.more)
                }
                .tint(BTTheme.accent)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .onChange(of: selectedTab) { oldTab, newTab in
                    if oldTab == .tuner, newTab != .tuner {
                        model.cancelRecordingStart()
                        if model.audioEngine.recording {
                            model.stopRecording()
                        }
                    }
                    if oldTab != newTab {
                        model.stopRecordingPlayback()
                        model.handlePracticeBackground()
                    }
                    // A tab is a top-level destination, not a continuation of a
                    // tool opened earlier. In particular, returning from
                    // Progress to Practice must not restore the Drone screen.
                    if newTab == .practice, oldTab != .practice {
                        practicePath = NavigationPath()
                        practiceNavigationGeneration = UUID()
                    }
                }
            }
        }
#if PHYSICAL_RELEASE
        .overlay(alignment: .topTrailing) {
            if physicalRoutePickerTestMode {
                PhysicalReleaseAudioRoutePicker()
                    .frame(width: 52, height: 52)
                    .padding(.top, 52)
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("physical.routePicker")
            }
        }
#endif
        .onChange(of: model.tutorialPresentationRequest) { _, _ in
            onboardingPresented = model.persistenceAccessState.canPersist
        }
        .onChange(of: model.persistenceAccessState) { _, accessState in
            if !accessState.canPersist {
                onboardingPresented = false
            }
        }
        .onChange(of: model.gatewayCompleted) { _, completed in
            if completed && !model.tutorialCompleted {
                onboardingPresented = true
            }
            routePendingDestinationIfReady()
        }
        .onChange(of: model.authState) { _, _ in
            routePendingDestinationIfReady()
        }
        .onChange(of: onboardingPresented) { _, presented in
            if !presented {
                routePendingDestinationIfReady()
            }
        }
        .onChange(of: scenePhase) { previousPhase, currentPhase in
#if PHYSICAL_RELEASE
            // AVRoutePickerView temporarily marks the scene inactive while its
            // system route sheet is presented. Physical-only route tests must
            // keep the graph alive across that transition; a real background
            // transition still follows the production teardown path below.
            if physicalRoutePickerTestMode, currentPhase == .inactive {
                return
            }
#endif
            AppSceneAudioLifecycle.handleTransition(
                from: previousPhase,
                to: currentPhase,
                preservePendingTunerStartWhileInactive: {
                    model.audioEngine.audioState == .permissionRequesting
                },
                cancelTunerStart: model.cancelRecordingStart,
                isTunerRecording: { model.audioEngine.recording },
                stopTunerRecording: model.stopRecording,
                releasePracticeAudio: {
                    model.stopRecordingPlayback()
                    model.handlePracticeBackground()
                    model.audioEngine.deactivateSessionImmediatelyIfIdle()
                }
            )
            if previousPhase == .active, currentPhase != .active {
                model.flushPendingPersistence()
            }
        }
        .task {
            if resetUITestState {
                model.resetForUITesting()
            }
            guard !uiTestMode else { return }
            await model.restoreSession()
            if model.gatewayCompleted && !model.tutorialCompleted {
                onboardingPresented = true
            }
        }
        .sheet(item: $guestAccountPromptMode) { mode in
            GatewayAuthForm(mode: mode)
        }
        .nativeSuccessFeedback()
    }

    private func practiceNavigation<Content: View>(
        path: Binding<NavigationPath>? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if let path {
                NavigationStack(path: path) { content() }
            } else {
                NavigationStack { content() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { practiceStatusBanners }
    }

    @ViewBuilder
    private var practiceStatusBanners: some View {
        VStack(spacing: BTSpacing.sm) {
            if let message = model.persistenceErrorMessage {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BTTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BTSpacing.lg)
                .padding(.vertical, BTSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BTTheme.surfaceWarm)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("app.persistenceError")
            }
            if model.guestProgressSafetyPromptEligible {
                GuestProgressSafetyBanner(
                    createAccount: {
                        model.markGuestProgressSafetyPromptHandled()
                        guestAccountPromptMode = .createAccount
                    },
                    keepPracticing: model.markGuestProgressSafetyPromptHandled
                )
                .padding(.horizontal, BTSpacing.lg)
            }
        }
    }

    private func routePendingDestinationIfReady() {
        guard model.gatewayCompleted, model.tutorialCompleted,
              let destination = model.consumePendingDestination() else { return }
        switch destination {
        case .classes:
            selectedTab = .more
        }
    }
}

#if PHYSICAL_RELEASE
private struct PhysicalReleaseAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.label
        picker.activeTintColor = UIColor.systemOrange
        picker.accessibilityIdentifier = "physical.routePicker"
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

func instrumentSetupAccessibilityAnnouncement() -> String {
    [
        NativeLocalization.string("Choose your instrument"),
        NativeLocalization.string("BrassTune uses your instrument for written notes and concert-pitch transposition."),
        NativeLocalization.string("You can change it later in Settings."),
    ].joined(separator: ". ")
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab
    @State private var originalInstrumentID: String?
    @AccessibilityFocusState private var setupHeaderFocused: Bool

    var body: some View {
        NavigationStack {
            BTScreen {
                VStack(alignment: .leading, spacing: BTSpacing.md) {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(BTTheme.accent)
                        .accessibilityHidden(true)
                    Text(verbatim: NativeLocalization.string("Choose your instrument"))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(BTTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: NativeLocalization.string(
                        "BrassTune uses your instrument for written notes and concert-pitch transposition."
                    ))
                        .font(.body)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: NativeLocalization.string("You can change it later in Settings."))
                        .font(.body)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(instrumentSetupAccessibilityAnnouncement())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($setupHeaderFocused)
                .accessibilityIdentifier("onboarding.hero")

                BTCard {
                    Picker(selection: $model.selectedInstrumentId) {
                        instrumentPickerOptions()
                    } label: {
                        Text(verbatim: NativeLocalization.string("Instrument"))
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("onboarding.instrumentPicker")
                }
            }
            .accessibilityIdentifier("screen.instrumentSetup")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    let isReviewing = model.tutorialCompleted
                    model.completeTutorial()
                    if !isReviewing {
                        selectedTab = .practice
                    }
                    isPresented = false
                } label: {
                    Label {
                        Text(verbatim: NativeLocalization.string("Continue to Practice"))
                    } icon: {
                        Image(systemName: "sun.max")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                .disabled(!model.persistenceAccessState.canPersist)
                .padding(.horizontal, BTSpacing.lg)
                .padding(.vertical, BTSpacing.sm)
                .background(.bar)
                .accessibilityIdentifier("onboarding.startPractice")
            }
            .toolbar {
                if model.tutorialCompleted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if let originalInstrumentID {
                                model.selectedInstrumentId = originalInstrumentID
                            }
                            isPresented = false
                        } label: {
                            Text(verbatim: NativeLocalization.string("Cancel"))
                        }
                        .accessibilityIdentifier("onboarding.cancel")
                    }
                }
            }
        }
        .onAppear {
            if originalInstrumentID == nil {
                originalInstrumentID = model.selectedInstrumentId
            }
            DispatchQueue.main.async {
                setupHeaderFocused = true
            }
        }
    }
}

struct PlayAlongView: View {
    @EnvironmentObject private var model: AppModel
    @State private var moreWaysExpanded: Bool

    init(libraryExpanded: Bool = false) {
        _moreWaysExpanded = State(initialValue: libraryExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            BTScreen {
                switch model.playAlongPhase {
                case .idle:
                    PlayAlongIdleView(moreWaysExpanded: $moreWaysExpanded)
                case .running:
                    if let session = model.playAlongSession {
                        PlayAlongLiveView(session: session)
                    }
                case .completed:
                    if let grade = model.playAlongGrade {
                        PlayAlongResultsView(
                            exercise: model.playAlongSession?.exercise ?? model.selectedPlayAlongExercise,
                            grade: grade
                        )
                    }
                }
            }
            .accessibilityIdentifier("screen.playAlong")
            if model.playAlongPhase == .idle {
                PlayAlongWarmupButton()
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.vertical, BTSpacing.sm)
                    .background(.bar)
            } else if model.playAlongPhase == .running {
                PlayAlongTransportBar()
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.vertical, BTSpacing.sm)
                    .background(.bar)
            }
        }
        .background(BTTheme.background.ignoresSafeArea())
        .navigationTitle("Play-Along")
        .navigationBarTitleDisplayMode(.inline)
    }
}

func playAlongAdvanceAnnouncement(for session: PlayAlongSession?) -> String? {
    guard let session else { return nil }
    if let note = session.currentNoteName {
        return NativeLocalization.format(
            "Next note is %@. Hold it steady for two seconds.",
            note
        )
    }
    return NativeLocalization.string("Exercise complete. Your results are ready.")
}

private struct PlayAlongLiveView: View {
    let session: PlayAlongSession
    @AccessibilityFocusState private var targetNoteFocused: Bool

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            Text(verbatim: NativeLocalization.format(
                "Note %@ of %@",
                String(min(session.currentNoteIndex + 1, session.exercise.writtenNotes.count)),
                String(session.exercise.writtenNotes.count)
            ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(BTTheme.muted)

            Text(verbatim: NativeLocalization.isolate(session.currentNoteName ?? "—"))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(BTTheme.accent)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(
                    playAlongAdvanceAnnouncement(for: session)
                        ?? NativeLocalization.string("Exercise complete. Your results are ready.")
                )
                .accessibilityFocused($targetNoteFocused)
                .accessibilityIdentifier("playAlong.targetNote")

            Text("Hold steady")
                .font(.headline)
                .frame(maxWidth: .infinity)

            ProgressView(value: session.heldFraction)
                .tint(BTTheme.success)
                .accessibilityLabel(Text(verbatim: NativeLocalization.string("Hold progress")))
                .accessibilityValue(NativeLocalization.format(
                    "%@ percent",
                    String(Int((session.heldFraction * 100).rounded()))
                ))
                .accessibilityIdentifier("playAlong.holdProgress")

            VStack(spacing: BTSpacing.xs) {
                Text(verbatim: session.detectedNoteName.map {
                    NativeLocalization.format("You're playing %@", $0)
                } ?? NativeLocalization.string("Listening…"))
                    .font(.title3.weight(.semibold))
                Text(verbatim: playAlongFeedback(session))
                    .font(.subheadline)
                    .foregroundStyle(playAlongFeedbackTint(session))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("playAlong.feedback")
        }

        PlayAlongSequenceView(session: session)
            .onAppear {
                guard UIAccessibility.isVoiceOverRunning else { return }
                DispatchQueue.main.async { targetNoteFocused = true }
            }
            .onChange(of: session.currentNoteIndex) { oldIndex, newIndex in
                guard oldIndex != newIndex, UIAccessibility.isVoiceOverRunning else { return }
                if session.currentNoteName == nil {
                    if let announcement = playAlongAdvanceAnnouncement(for: session) {
                        UIAccessibility.post(notification: .announcement, argument: announcement)
                    }
                } else {
                    targetNoteFocused = false
                    DispatchQueue.main.async { targetNoteFocused = true }
                }
            }
    }
}

private struct PlayAlongSequenceView: View {
    let session: PlayAlongSession
    @ScaledMetric(relativeTo: .headline) private var noteCellSize = 44

    var body: some View {
        BTCard {
            BTSectionHeader(title: "Exercise")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BTSpacing.sm) {
                    ForEach(Array(session.exercise.writtenNotes.enumerated()), id: \.offset) { index, note in
                        let completed = index < session.noteGrades.count
                        let active = index == session.currentNoteIndex
                        let tint = completed
                            ? playAlongRatingTint(session.noteGrades[index].rating)
                            : (active ? BTTheme.accent : BTTheme.muted)
                        Text(verbatim: NativeLocalization.isolate(note))
                            .font(.headline.monospaced())
                            .foregroundStyle(tint)
                            .frame(
                                minWidth: max(44, noteCellSize),
                                minHeight: max(44, noteCellSize)
                            )
                            .fixedSize(horizontal: true, vertical: true)
                            .background(tint.opacity(active || completed ? 0.15 : 0.06), in: Circle())
                            .overlay {
                                Circle().stroke(tint.opacity(active ? 0.75 : 0.25), lineWidth: active ? 2 : 1)
                            }
                            .accessibilityLabel(NativeLocalization.format(
                                "%@, %@",
                                note,
                                completed ? session.noteGrades[index].rating.title : (active ? NativeLocalization.string("current note") : NativeLocalization.string("up next"))
                            ))
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .accessibilityIdentifier("playAlong.sequence")
        }
    }
}

private struct PlayAlongResultsView: View {
    @EnvironmentObject private var model: AppModel
    let exercise: PlayAlongExercise
    let grade: PlayAlongGrade

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            BTSectionHeader(title: "Your score", subtitle: .verbatim(exercise.displayTitle))

            Text(verbatim: NativeLocalization.isolate("\(grade.inTunePercentage)%"))
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(playAlongScoreTint(grade.inTunePercentage))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("playAlong.score")

            HStack(spacing: BTSpacing.sm) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < grade.stars ? "star.fill" : "star")
                        .foregroundStyle(index < grade.stars ? BTTheme.accent : BTTheme.muted)
                }
            }
            .font(.title2)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(NativeLocalization.format(
                "%@ out of 3 stars",
                String(grade.stars)
            ))

            Text(verbatim: playAlongScoreMessage(grade))
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: BTSpacing.md) {
                BTMetricTile(
                    title: "Notes played",
                    value: .verbatim("\(grade.notesPlayed)/\(grade.totalNotes)"),
                    detail: "completed"
                )
                BTMetricTile(
                    title: "Average",
                    value: .verbatim(grade.averageAbsoluteCents.map { String(format: "%.1f", $0) } ?? "—"),
                    detail: "cents from center",
                    tint: BTTheme.secondaryAccent
                )
            }
        }

        BTCard {
            BTSectionHeader(title: "Note by note", subtitle: "Cents show the small distance from the center of a note.")
            ForEach(grade.noteGrades) { noteGrade in
                HStack {
                    Text(verbatim: NativeLocalization.isolate(noteGrade.writtenNoteName))
                        .font(.headline.monospaced())
                    Spacer()
                    Text(verbatim: noteGrade.medianCents.map {
                        NativeLocalization.format("%@ cents", String(format: "%+.1f", $0))
                    } ?? NativeLocalization.string("Skipped"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(playAlongRatingTint(noteGrade.rating))
                    Text(verbatim: noteGrade.rating.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(playAlongRatingTint(noteGrade.rating))
                }
                .accessibilityElement(children: .combine)
            }
        }

        Button {
            Task {
                await model.startPlayAlong(exerciseID: exercise.id)
            }
        } label: {
            Label("Play again", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
        .accessibilityIdentifier("playAlong.playAgain")

        Button {
            model.resetPlayAlong()
        } label: {
            Label("Choose another exercise", systemImage: "music.note.list")
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .accessibilityIdentifier("playAlong.chooseAnother")
    }
}

private struct PlayAlongTransportBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: BTSpacing.lg) {
            Button {
                model.skipPlayAlongNote()
            } label: {
                Label("Skip note", systemImage: "forward.end.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playAlong.skip")

            Divider()
                .frame(height: 24)

            Button(role: .destructive) {
                model.stopPlayAlong()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playAlong.stop")
        }
        .font(.headline)
        .foregroundStyle(BTTheme.text)
        .padding(.horizontal, BTSpacing.xl)
        .padding(.vertical, BTSpacing.md)
        .brassGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playAlong.transport")
    }
}

struct TunerView: View {
    @EnvironmentObject private var model: AppModel
    // Observe the engine directly so the readout, record button, and floating
    // transport re-render live as frames/recording change (SwiftUI does not
    // subscribe to a nested ObservableObject reached through `model`).
    @EnvironmentObject private var audioEngine: NativeAudioEngine
    @AccessibilityFocusState private var microphoneIssueFocused: Bool
    @State private var lastFocusedMicrophoneIssue: String?
    @State private var microphoneRationalePresentation: MicrophoneRationalePresentation?

    private var activeFrame: PitchFrame? {
        guard audioEngine.recording else { return nil }
        guard audioEngine.activeSource == .live || model.testFixturesEnabled else { return nil }
        return audioEngine.currentFrame
    }

    private var language: AppLanguage {
        AppLanguage.launchOverride ?? model.appLanguage
    }

    /// A deterministic launch-only state keeps the UI contract testable without
    /// teaching the detector about presentation fixtures. It deliberately
    /// supplies a populated but low-confidence frame, the state that must not
    /// publish provisional measurements.
    private var estimatingReadoutFixture: PitchFrame? {
        guard model.testFixturesEnabled,
              ProcessInfo.processInfo.arguments.contains("UITEST_TUNER_ESTIMATING_FRAME") else {
            return nil
        }
        return PitchFrame(
            timestampMs: 0,
            frequencyHz: 440,
            confidence: 0.4,
            rms: 0.08,
            centsDeviation: 0,
            tuningStatus: .unstable,
            writtenNoteName: "A",
            writtenOctave: 4,
            isValidForRecording: false
        )
    }

    private var stableReadoutFixture: PitchFrame? {
        guard model.testFixturesEnabled,
              ProcessInfo.processInfo.arguments.contains("UITEST_TUNER_STABLE_FRAME") else {
            return nil
        }
        return PitchFrame(
            timestampMs: 0,
            frequencyHz: 440,
            confidence: 0.98,
            rms: 0.08,
            centsDeviation: 0,
            tuningStatus: .inTune,
            writtenNoteName: "A",
            writtenOctave: 4,
            isValidForRecording: true
        )
    }

    private var readoutFrame: PitchFrame? {
        estimatingReadoutFixture ?? stableReadoutFixture ?? activeFrame
    }

    private var readoutState: NativeAudioOperationalState {
        if estimatingReadoutFixture != nil {
            return .permissionGranted(.estimating)
        }
        if stableReadoutFixture != nil {
            return .permissionGranted(.stable)
        }
        return audioEngine.audioState
    }

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: .verbatim(language.localized("Tuner")),
                title: .verbatim(language.localized("Find the center")),
                subtitle: .verbatim(language.localized("Play a note and BrassTune will show whether it is flat, in tune, or sharp."))
            )

            TunerReadout(
                frame: readoutFrame,
                state: readoutState,
                instrumentName: instrumentDisplayName(model.selectedInstrumentId)
            )
            .accessibilityFocused($microphoneIssueFocused)

            NavigationLink {
                DroneIntervalView()
            } label: {
                Label("Open drone and interval tuning", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("tuner.droneIntervalLink")

            if !shouldPresentRecoveryActions, let notice = audioEngine.audioNotice {
                Text(verbatim: notice)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tuner.audioNotice")
            }
        }
        .accessibilityIdentifier("screen.tuner")
        .safeAreaInset(edge: .bottom) {
            if audioEngine.recording {
                FloatingPracticeControlBar()
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.bottom, BTSpacing.md)
            } else if shouldPresentRecoveryActions {
                MicrophoneRecoveryActions {
                    Task { await model.startRecording() }
                }
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.bottom, BTSpacing.md)
            } else {
                VStack(spacing: BTSpacing.sm) {
                    Text("Tap Start Listening, allow microphone access, then play for 2–3 seconds.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.tunerSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tuner.microphoneGuidance")
                    Button {
                        beginListening()
                    } label: {
                        Label("Start listening", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .disabled(model.recordingStartInProgress)
                    .accessibilityIdentifier("tuner.recordButton")
                }
                .padding(.horizontal, BTSpacing.lg)
                .padding(.bottom, BTSpacing.md)
            }
        }
        .onAppear { focusMicrophoneIssueIfNeeded() }
        .onChange(of: microphoneIssueMessage) { _, _ in
            focusMicrophoneIssueIfNeeded()
        }
        .sheet(item: $microphoneRationalePresentation) { _ in
            MicrophoneRationaleView()
        }
    }

    private var shouldPresentRecoveryActions: Bool {
        switch audioEngine.audioState {
        case .permissionDenied, .permissionRestrictedOrUnavailable,
             .permissionGranted(.interrupted), .permissionGranted(.routeChanged),
             .permissionGranted(.recoverableError), .permissionGranted(.fatalError):
            return true
        default:
            return model.lastError == .microphoneUnavailable
        }
    }

    private var microphoneIssueMessage: String? {
        guard shouldPresentRecoveryActions else { return nil }
        return tunerOperationalCopy(for: audioEngine.audioState).detail
    }

    private func focusMicrophoneIssueIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning,
              let message = microphoneIssueMessage else {
            lastFocusedMicrophoneIssue = nil
            return
        }
        guard lastFocusedMicrophoneIssue != message else { return }
        lastFocusedMicrophoneIssue = message
        DispatchQueue.main.async { microphoneIssueFocused = true }
    }

    private func beginListening() {
        if model.microphoneRationaleSeen {
            Task { await model.startRecording() }
        } else {
            microphoneRationalePresentation = MicrophoneRationalePresentation()
        }
    }
}

private struct MicrophoneRationalePresentation: Identifiable {
    let id = UUID()
}

private struct MicrophoneRationaleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BTSpacing.lg) {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(BTTheme.accent)
                    .accessibilityHidden(true)
                Text("Microphone access")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: NativeLocalization.string(
                    "Practice recordings and imported sheet music stay on this device unless you choose to share or export them."
                ))
                    .foregroundStyle(BTTheme.tunerSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("microphone.rationaleDisclosure")
                Text("Your first tap asks for microphone access.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.tunerSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    model.markMicrophoneRationaleSeen()
                    dismiss()
                    Task { await model.startRecording() }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("microphone.rationaleContinue")
                Button {
                    model.markMicrophoneRationaleSeen()
                    dismiss()
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("microphone.rationaleNotNow")
            }
            .padding(BTSpacing.xl)
            .background(BTTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
        .accessibilityIdentifier("microphone.rationale")
    }
}

private struct TunerReadout: View {
    let frame: PitchFrame?
    let state: NativeAudioOperationalState
    let instrumentName: String
    @EnvironmentObject private var model: AppModel

    private var language: AppLanguage {
        AppLanguage.launchOverride ?? model.appLanguage
    }

    private var hasUsablePitch: Bool {
        frame?.frequencyHz != nil && frame?.writtenNoteName != nil
    }

    private var hasStableTunerFrame: Bool {
        guard let frame else { return false }
        return NativeAudioEngine.isStableTunerFrame(frame)
    }

    private var noteLabel: String {
        guard isStable, let note = frame?.writtenNoteName else {
            return operationalCopy.title
        }
        return NativeLocalization.isolate("\(note)\(frame?.writtenOctave.map(String.init) ?? "")")
    }

    private var verdict: String {
        guard isStable, let frame else { return operationalCopy.detail }
        switch frame.tuningStatus {
        case .inTune: return language.localized("In tune — hold it steady")
        case .sharp: return language.localized("A little sharp — ease down")
        case .flat: return language.localized("A little flat — lift up")
        case .silence, .noLock, .unstable: return language.localized("Listening…")
        }
    }

    private var tint: Color {
        guard isStable else { return operationalCopy.tint }
        guard let frame else { return BTTheme.tunerSecondaryText }
        switch frame.tuningStatus {
        case .inTune: return BTTheme.success
        case .sharp: return BTTheme.sharp
        case .flat: return BTTheme.flat
        case .silence, .noLock, .unstable: return BTTheme.tunerSecondaryText
        }
    }

    private var isStable: Bool {
        state == .permissionGranted(.stable) && hasUsablePitch && hasStableTunerFrame
    }

    private var operationalCopy: TunerOperationalCopy {
        tunerOperationalCopy(for: state)
    }

    private var signedCents: String? {
        guard isStable, let cents = frame?.centsDeviation else { return nil }
        let rounded = Int(cents.rounded())
        return NativeLocalization.isolate("\(rounded > 0 ? "+" : "")\(rounded) cents")
    }

    var body: some View {
        BTCard(tint: isStable ? BTTheme.surfaceWarm : BTTheme.surfaceAlt) {
            Label {
                Text(verbatim: NativeLocalization.string(operationalCopy.title))
            } icon: {
                Image(systemName: operationalCopy.systemImage)
            }
                .font(.headline)
                .foregroundStyle(operationalCopy.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tuner.signalState")

            Text(verbatim: noteLabel)
                .font(.system(isStable ? .largeTitle : .title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuner.note")

            Text(verbatim: verdict)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("tuner.verdict")

            if isStable {
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    if let signedCents {
                        tunerNumericRow("Cents", value: signedCents, identifier: "tuner.cents")
                    }
                    if let frequency = frame?.frequencyHz {
                        tunerNumericRow(
                            "Frequency",
                            value: NativeLocalization.isolate(String(format: "%.1f Hz", frequency)),
                            identifier: "tuner.frequency"
                        )
                    }
                    tunerNumericRow(
                        "Confidence",
                        value: NativeLocalization.isolate("\(Int(((frame?.confidence ?? 0) * 100).rounded()))%"),
                        identifier: "tuner.confidence"
                    )
                    tunerNumericRow("Instrument", value: instrumentName, identifier: "tuner.instrument")
                }
                .accessibilityElement(children: .contain)
            }

            if isStable {
                TuningMeter(cents: frame?.centsDeviation)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: tunerVoiceOverState(frame: frame, isListening: isStable, state: state)))
        .accessibilityIdentifier("tuner.readout")
    }

    private func tunerNumericRow(_ title: String, value: String, identifier: String) -> some View {
        HStack {
            Text(verbatim: NativeLocalization.string(title))
                .foregroundStyle(BTTheme.tunerSecondaryText)
            Spacer()
            Text(verbatim: value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(BTTheme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct TunerOperationalCopy {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private func tunerOperationalCopy(for state: NativeAudioOperationalState) -> TunerOperationalCopy {
    switch state {
    case .permissionNotDetermined:
        return .init(title: "Microphone not started", detail: "Start listening when you are ready.", systemImage: "mic", tint: BTTheme.tunerSecondaryText)
    case .permissionRequesting:
        return .init(title: "Requesting microphone access", detail: "Waiting for your iOS permission choice.", systemImage: "mic.badge.plus", tint: BTTheme.accent)
    case .permissionDenied:
        return .init(title: "Microphone access is off", detail: "Allow microphone access in iOS Settings, then try again.", systemImage: "mic.slash.fill", tint: BTTheme.warning)
    case .permissionRestrictedOrUnavailable:
        return .init(title: "Microphone unavailable", detail: "BrassTune cannot hear a microphone on this device right now.", systemImage: "mic.slash.fill", tint: BTTheme.warning)
    case .permissionGranted(.idle):
        return .init(title: "Microphone available", detail: "Start listening, then play a comfortable note.", systemImage: "mic", tint: BTTheme.tunerSecondaryText)
    case .permissionGranted(.starting):
        return .init(title: "Starting microphone", detail: "Preparing the audio input.", systemImage: "waveform", tint: BTTheme.accent)
    case .permissionGranted(.listeningNoSignal):
        return .init(title: "Listening — no signal", detail: "Play for a moment at a comfortable volume.", systemImage: "ear", tint: BTTheme.tunerSecondaryText)
    case .permissionGranted(.estimating):
        return .init(title: "Finding your note", detail: "Keep the note steady while BrassTune estimates pitch.", systemImage: "waveform.path", tint: BTTheme.secondaryAccent)
    case .permissionGranted(.stable):
        return .init(title: "Signal locked", detail: "Pitch is available.", systemImage: "checkmark.circle.fill", tint: BTTheme.success)
    case .permissionGranted(.interrupted):
        return .init(title: "Microphone interrupted", detail: "Recording stopped because another audio session took over.", systemImage: "pause.circle", tint: BTTheme.warning)
    case .permissionGranted(.routeChanged):
        return .init(title: "Audio route changed", detail: "Check your headphones or speaker before listening again.", systemImage: "headphones", tint: BTTheme.warning)
    case .permissionGranted(.recoverableError):
        return .init(title: "Microphone needs attention", detail: "BrassTune could not start the microphone. Check your audio input and retry.", systemImage: "exclamationmark.triangle", tint: BTTheme.warning)
    case .permissionGranted(.fatalError):
        return .init(title: "Microphone unavailable", detail: "BrassTune could not continue this microphone session.", systemImage: "xmark.octagon", tint: BTTheme.danger)
    }
}

func tunerVoiceOverState(
    frame: PitchFrame?,
    isListening: Bool,
    state: NativeAudioOperationalState? = nil
) -> String {
    guard isListening else {
        guard let state else {
            return [
                NativeLocalization.string("Play a note"),
                NativeLocalization.string("Ready"),
            ].joined(separator: ", ")
        }
        return [
            tunerOperationalCopy(for: state).title,
            tunerOperationalCopy(for: state).detail,
        ].joined(separator: ", ")
    }
    guard let frame,
          frame.isValidForRecording,
          let note = frame.writtenNoteName,
          let cents = frame.centsDeviation else {
        return [
            NativeLocalization.string("Play a note"),
            NativeLocalization.string("Listening…"),
        ].joined(separator: ", ")
    }

    let noteAndOctave = NativeLocalization.isolate(
        "\(note)\(frame.writtenOctave.map(String.init) ?? "")"
    )
    let direction: String
    if abs(cents) <= 5 {
        let roundedCents = Int(cents.rounded())
        let centeredCents = roundedCents > 0 ? "+\(roundedCents)" : String(roundedCents)
        direction = [
            NativeLocalization.format("%@ cents", centeredCents),
            NativeLocalization.string("In tune"),
        ].joined(separator: ", ")
    } else {
        let quantizedMagnitude = max(5, Int((abs(cents) / 5).rounded()) * 5)
        direction = NativeLocalization.format(
            cents > 0 ? "%@ cents sharp — ease down" : "%@ cents flat — lift up",
            String(quantizedMagnitude)
        )
    }
    return [noteAndOctave, direction].joined(separator: ", ")
}

private struct TuningMeter: View {
    let cents: Double?
    @Environment(\.layoutDirection) private var interfaceLayoutDirection

    private var clampedCents: Double {
        min(50, max(-50, cents ?? 0))
    }

    private var accessibilityVerdict: String {
        guard let cents else { return NativeLocalization.string("Waiting for a note") }
        if abs(cents) <= 5 { return NativeLocalization.string("In tune") }
        return cents > 0 ? NativeLocalization.string("Sharp") : NativeLocalization.string("Flat")
    }

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            GeometryReader { proxy in
                ZStack {
                    Capsule()
                        .fill(BTTheme.surfaceAlt)
                        .frame(height: 14)
                    Capsule()
                        .fill(BTTheme.success.opacity(0.30))
                        .frame(width: max(18, proxy.size.width * 0.10), height: 14)
                    Rectangle()
                        .fill(BTTheme.text)
                        .frame(width: 4, height: 34)
                        .clipShape(Capsule())
                        .offset(x: tuningMeterIndicatorOffset(
                            cents: clampedCents,
                            width: proxy.size.width
                        ))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 40)
            .environment(\.layoutDirection, .leftToRight)

            ViewThatFits(in: .horizontal) {
                HStack {
                    tuningAxisLabel("Flat", systemImage: "arrow.down", tint: BTTheme.flat)
                    Spacer()
                    Text("In tune")
                        .foregroundStyle(BTTheme.success)
                        .environment(\.layoutDirection, interfaceLayoutDirection)
                    Spacer()
                    tuningAxisLabel("Sharp", systemImage: "arrow.up", tint: BTTheme.sharp)
                }
                VStack(spacing: BTSpacing.xs) {
                    tuningAxisLabel("Flat", systemImage: "arrow.down", tint: BTTheme.flat)
                    Text("In tune")
                        .foregroundStyle(BTTheme.success)
                    tuningAxisLabel("Sharp", systemImage: "arrow.up", tint: BTTheme.sharp)
                }
            }
            .font(.caption.weight(.semibold))
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: NativeLocalization.string("Tuning meter")))
        .accessibilityValue(accessibilityVerdict)
        .accessibilityIdentifier("tuner.meter")
    }

    private func tuningAxisLabel(_ title: BTCopy, systemImage: String, tint: Color) -> some View {
        Label {
            Text(verbatim: title.resolved)
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .foregroundStyle(tint)
        .environment(\.layoutDirection, interfaceLayoutDirection)
    }
}

func tuningMeterIndicatorOffset(cents: Double?, width: CGFloat) -> CGFloat {
    let clamped = min(50, max(-50, cents ?? 0))
    let travel = max(0, width / 2 - 5)
    return CGFloat(clamped / 50) * travel
}

private struct FloatingPracticeControlBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            HStack(spacing: BTSpacing.sm) {
                Button {
                    model.stopRecording()
                } label: {
                    Label("Stop and save", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(verbatim: NativeLocalization.string("Stop and save recording")))
                .accessibilityIdentifier("tuner.floating.stop")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.danger))

                Button {
                    model.toggleMetronome()
                } label: {
                    Label {
                        Text(verbatim: NativeLocalization.string(model.metronomeRunning ? "Stop metronome" : "Start metronome"))
                    } icon: {
                        Image(systemName: model.metronomeRunning ? "pause.fill" : "play.fill")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(verbatim: NativeLocalization.string(model.metronomeRunning ? "Stop metronome" : "Start metronome")))
                .accessibilityIdentifier("tuner.floating.metronome")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.warning))

                VStack(spacing: 0) {
                    Text(verbatim: NativeLocalization.isolate(String(model.metronome.bpm)))
                        .font(.headline.monospacedDigit())
                    Text("BPM")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BTTheme.muted)
                }
                .frame(minWidth: 52)
                .accessibilityElement(children: .combine)

                Button {
                    model.adjustTempo(by: -2)
                } label: {
                    Label("Tempo down", systemImage: "minus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(verbatim: NativeLocalization.string("Decrease tempo")))
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))

                Button {
                    model.adjustTempo(by: 2)
                } label: {
                    Label("Tempo up", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(verbatim: NativeLocalization.string("Increase tempo")))
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))
            }

            Text(verbatim: NativeLocalization.string(model.metronomeRunning ? "Visual beat while recording" : "Recording"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.metronomeRunning ? BTTheme.warning : BTTheme.muted)
                .scaleEffect(model.metronomeRunning && !reduceMotion ? 1.02 : 1)
        }
        .padding(BTSpacing.md)
        .brassGlass(cornerRadius: BTTheme.radiusLarge, interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuner.floatingBar")
    }
}

private struct FloatingIconButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.60 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTSectionHeader(
                title: "Practice history",
                subtitle: "Your saved recordings, newest first."
            )

            if model.sessions.isEmpty {
                BTEmptyState(
                    title: "No recordings yet",
                    message: "Use the Tuner or finish a Play-Along exercise to save your first recording.",
                    systemImage: "waveform"
                )
                .accessibilityIdentifier("sessions.empty")
            } else {
                ForEach(model.sessions) { session in
                    NavigationLink {
                        SessionDetailView(sessionID: session.id)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sessions.row.\(session.id.uuidString)")
                }
            }
        }
        .navigationTitle("Practice history")
        .accessibilityIdentifier("screen.sessions")
    }
}

private struct SessionRow: View {
    let session: PracticeSession

    var body: some View {
        BTCard {
            HStack(alignment: .top, spacing: BTSpacing.md) {
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(verbatim: session.name)
                        .font(.headline)
                        .foregroundStyle(BTTheme.text)
                        .accessibilityIdentifier("sessions.sessionName")
                    Text(verbatim: NativeLocalization.format(
                        "%@ · %@",
                        session.startedAt.formatted(date: .abbreviated, time: .shortened),
                        instrumentDisplayName(session.instrumentId)
                    ))
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }
                Spacer()
                Text(verbatim: NativeLocalization.format(
                    "%@%% in tune",
                    String(Int(session.inTunePercentage.rounded()))
                ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    let sessionID: PracticeSession.ID

    private var session: PracticeSession? {
        model.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        BTScreen {
            if let session {
                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(
                        title: .verbatim(session.name),
                        subtitle: .verbatim(session.startedAt.formatted(date: .complete, time: .shortened))
                    )
                    Text(verbatim: NativeLocalization.isolate("\(Int(session.inTunePercentage.rounded()))%"))
                        .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                        .accessibilityIdentifier("session.score")
                    Text(verbatim: NativeLocalization.string(session.inTunePercentage >= 70
                        ? "You found the center often. Keep building that steady sound."
                        : "Slow down and hold each note steady before moving on."))
                        .font(.headline)
                }

                BTCard {
                    BTSectionHeader(
                        title: "Details",
                        subtitle: "A cent is a very small pitch step. Smaller numbers are closer to the center."
                    )
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(
                            title: "Average distance",
                            value: .verbatim(String(format: "%.1f", session.averageAbsCents)),
                            detail: "cents"
                        )
                        BTMetricTile(
                            title: "In tune",
                            value: .verbatim(NativeLocalization.isolate("\(Int(session.inTunePercentage.rounded()))%")),
                            detail: "within 5 cents",
                            tint: BTTheme.success
                        )
                    }
                    Text(verbatim: NativeLocalization.format("Notes heard: %@", session.pitchCoverageLabel))
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }

                SessionListenBackCard(
                    player: model.recordingPlayer,
                    session: session,
                    recordingURL: model.availableRecordingURL(for: session)
                )

                PracticeReflectionCard(sessionID: session.id)

                BTCard {
                    BTSectionHeader(title: "Share", subtitle: "Send a text summary when you want feedback.")
                    ShareLink(item: session.exportText) {
                        Label("Share recording summary", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("session.exportButton")
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete recording", systemImage: "trash")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("session.deleteButton")
            } else {
                BTEmptyState(
                    title: "Recording deleted",
                    message: "This recording is no longer on this device.",
                    systemImage: "checkmark.circle"
                )
            }
        }
        .navigationTitle("Recording")
        .accessibilityIdentifier("screen.sessionDetail")
        .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) {
                if let session {
                    model.deleteSession(id: session.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .onDisappear {
            guard let session,
                  model.recordingPlayer.loadedURL == model.availableRecordingURL(for: session) else { return }
            model.stopRecordingPlayback()
        }
    }
}

private struct SessionListenBackCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: NativeRecordingPlayer
    let session: PracticeSession
    let recordingURL: URL?

    private var isThisRecordingPlaying: Bool {
        player.loadedURL == recordingURL && player.state == .playing
    }

    var body: some View {
        BTCard(tint: recordingURL == nil ? BTTheme.surfaceWarm : BTTheme.surface) {
            if recordingURL != nil {
                BTSectionHeader(
                    title: "Listen back",
                    subtitle: "Hear your take and choose one small thing to improve next time."
                )

                if player.loadedURL == recordingURL {
                    ProgressView(
                        value: min(max(0, player.currentTime), max(0.01, player.duration)),
                        total: max(0.01, player.duration)
                    )
                    .tint(BTTheme.accent)
                    .accessibilityLabel("Recording progress")
                    Text(verbatim: "\(playbackTime(player.currentTime)) / \(playbackTime(player.duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BTTheme.muted)
                }

                HStack(spacing: BTSpacing.sm) {
                    Button {
                        model.toggleRecordingPlayback(for: session)
                    } label: {
                        Label {
                            Text(verbatim: NativeLocalization.string(
                                isThisRecordingPlaying
                                    ? "Pause"
                                    : (player.state == .paused && player.loadedURL == recordingURL ? "Resume" : "Play recording")
                            ))
                        } icon: {
                            Image(systemName: isThisRecordingPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("session.listenBack.toggle")

                    Button {
                        player.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .disabled(player.loadedURL != recordingURL || player.state == .stopped)
                    .accessibilityIdentifier("session.listenBack.stop")
                }

                Text("Saved only inside BrassTune on this device. Listen-back uses media playback, so the Ring/Silent switch does not mute it.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)

                if let notice = player.notice {
                    Label {
                        Text(verbatim: notice)
                    } icon: {
                        Image(systemName: "speaker.badge.exclamationmark")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BTTheme.warning)
                    .accessibilityIdentifier("session.listenBack.notice")
                }
            } else {
                BTSectionHeader(
                    title: "Listen-back unavailable",
                    subtitle: "This session still has its pitch results, but it does not have a usable audio file on this device."
                )
                Label("Your practice details are safe.", systemImage: "waveform.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BTTheme.muted)
                    .accessibilityIdentifier("session.listenBack.unavailable")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.listenBack")
    }

    private func playbackTime(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

func playAlongFeedback(_ session: PlayAlongSession) -> String {
    guard let target = session.currentNoteName else { return NativeLocalization.string("Exercise complete") }
    guard PracticePitchMath.matchesPitchClass(session.detectedNoteName, target), let cents = session.detectedCents else {
        return session.detectedNoteName == nil
            ? NativeLocalization.format("Play %@", target)
            : NativeLocalization.format("Move to %@", target)
    }
    let rounded = Int(cents.rounded())
    if abs(rounded) <= 5 {
        return NativeLocalization.string("In tune — hold steady")
    }
    return rounded > 0
        ? NativeLocalization.format("%@ cents sharp — ease down", String(abs(rounded)))
        : NativeLocalization.format("%@ cents flat — lift up", String(abs(rounded)))
}

func playAlongFeedbackTint(_ session: PlayAlongSession) -> Color {
    guard PracticePitchMath.matchesPitchClass(session.detectedNoteName, session.currentNoteName), let cents = session.detectedCents else {
        return BTTheme.muted
    }
    if abs(cents) <= 5 { return BTTheme.success }
    return cents > 0 ? BTTheme.sharp : BTTheme.flat
}

private func playAlongRatingTint(_ rating: PlayAlongNoteRating) -> Color {
    switch rating {
    case .excellent: return BTTheme.success
    case .good: return BTTheme.secondaryAccent
    case .close: return BTTheme.warning
    case .off, .missed: return BTTheme.danger
    }
}

private func playAlongScoreTint(_ score: Int) -> Color {
    switch score {
    case 85...: return BTTheme.success
    case 60...: return BTTheme.secondaryAccent
    default: return BTTheme.warning
    }
}

private func playAlongScoreMessage(_ grade: PlayAlongGrade) -> String {
    switch grade.stars {
    case 3: return NativeLocalization.string("Strong work — try to beat your best.")
    case 2: return NativeLocalization.string("Nice start. One more round can make it steadier.")
    case 1: return NativeLocalization.string("Keep going. Slow, even air will help.")
    default: return NativeLocalization.string("Try again when you're ready.")
    }
}

private func practiceTimeLabel(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return NativeLocalization.isolate("\(Int(seconds.rounded()))s")
    }
    return NativeLocalization.isolate("\(Int((seconds / 60).rounded()))m")
}
struct MetronomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advancedRhythmExpanded = false

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Tools",
                title: "Metronome",
                subtitle: "Keep a steady beat while you practice.",
                trailing: model.metronomeRunning ? "Running" : "Ready"
            )

            BTCard(tint: BTTheme.surfaceWarm) {
                HStack(alignment: .center, spacing: BTSpacing.lg) {
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        Text(verbatim: NativeLocalization.isolate(String(model.metronome.bpm)))
                            .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(BTTheme.accentSoft)
                            .accessibilityIdentifier("metronome.bpm")
                        Text(verbatim: NativeLocalization.format(
                            "%@ • %@",
                            model.metronome.meterLabel,
                            model.metronome.subdivision.title
                        ))
                            .font(.headline)
                            .foregroundStyle(BTTheme.muted)
                            .accessibilityIdentifier("metronome.meter")
                    }
                    Spacer()
                    Circle()
                        .fill(model.metronomeRunning ? BTTheme.warning.opacity(0.90) : BTTheme.surfaceAlt)
                        .frame(width: 74, height: 74)
                        .scaleEffect(model.metronomeRunning && !reduceMotion ? 1.0 + CGFloat(model.metronomeTick == 0 ? 0.18 : 0.06) : 1)
                        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: model.metronomeTick)
                        .accessibilityHidden(true)
                }

                Button {
                    model.toggleMetronome()
                } label: {
                    Label { Text(verbatim: NativeLocalization.string(model.metronomeRunning ? "Stop metronome" : "Start metronome")) } icon: { Image(systemName: model.metronomeRunning ? "pause.fill" : "play.fill") }
                }
                .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                .accessibilityIdentifier("metronome.toggle")
            }

            BTCard {
                BTSectionHeader(title: "Tempo", subtitle: "Tap the beat or adjust it one step at a time.")
                HStack(spacing: BTSpacing.md) {
                    Button {
                        model.adjustTempo(by: -5)
                    } label: {
                        Label("Down", systemImage: "minus")
                    }
                    .buttonStyle(BTSecondaryButtonStyle(horizontalPadding: BTSpacing.xs))
                    .accessibilityIdentifier("metronome.tempoDown")

                    Button {
                        model.tapTempo()
                    } label: {
                        Label("Tap tempo", systemImage: "hand.tap")
                    }
                    .buttonStyle(BTSecondaryButtonStyle(horizontalPadding: BTSpacing.xs))
                    .accessibilityIdentifier("metronome.tapTempo")

                    Button {
                        model.adjustTempo(by: 5)
                    } label: {
                        Label("Up", systemImage: "plus")
                    }
                    .buttonStyle(BTSecondaryButtonStyle(horizontalPadding: BTSpacing.xs))
                    .accessibilityIdentifier("metronome.tempoUp")
                }
                Stepper(value: Binding(get: { model.metronome.bpm }, set: { model.setTempo($0) }), in: 20...300, step: 1) {
                    Text(verbatim: NativeLocalization.format("BPM %@", String(model.metronome.bpm)))
                }
                    .accessibilityIdentifier("metronome.stepper")
            }

            BTCard {
                BTSectionHeader(title: "Sound and feel", subtitle: "The click is on by default. Use visual-only mode whenever you want silence.")
                Picker("Meter", selection: Binding(
                    get: { model.metronome.beatsPerMeasure },
                    set: { model.setMeter(beats: $0, unit: model.metronome.beatUnit) }
                )) {
                    ForEach([2, 3, 4, 5, 6, 7, 9, 12], id: \.self) { beats in
                        Text(verbatim: NativeLocalization.isolate("\(beats)/\(model.metronome.beatUnit)")).tag(beats)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("metronome.meterPicker")

                Picker("Subdivision", selection: Binding(get: { model.metronome.subdivision }, set: { model.metronome.subdivision = $0 })) {
                    ForEach(MetronomeSubdivision.allCases) { subdivision in
                        Text(verbatim: subdivision.title).tag(subdivision)
                    }
                }
                .accessibilityIdentifier("metronome.subdivisionPicker")

                Toggle("Visual-only metronome", isOn: Binding(get: { model.metronome.visualOnly }, set: { model.setMetronomeVisualOnly($0) }))
                .accessibilityIdentifier("metronome.visualOnly")
                .accessibilityHint(Text(verbatim: NativeLocalization.string("Visual-only mode gives you a silent beat.")))

                Toggle("Haptic pulse", isOn: Binding(get: { model.metronome.hapticsEnabled }, set: { model.metronome.hapticsEnabled = $0 }))
                    .accessibilityIdentifier("metronome.haptics")

                Slider(value: Binding(get: { model.metronome.volume }, set: { model.setMetronomeVolume($0) }), in: 0...1)
                    .disabled(model.metronome.visualOnly)
                    .accessibilityLabel(Text(verbatim: NativeLocalization.string("Metronome volume")))
                    .accessibilityIdentifier("metronome.volume")

                Divider()

                DisclosureGroup(isExpanded: $advancedRhythmExpanded) {
                    VStack(alignment: .leading, spacing: BTSpacing.md) {
                        Picker("Beat unit", selection: Binding(
                            get: { model.metronome.beatUnit },
                            set: { model.setMeter(beats: model.metronome.beatsPerMeasure, unit: $0) }
                        )) {
                            ForEach([2, 4, 8, 16], id: \.self) { unit in
                                Text(verbatim: NativeLocalization.isolate("1/\(unit)")).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("metronome.beatUnitPicker")

                        Toggle("Accent first beat", isOn: $model.metronome.accentFirstBeat)
                            .accessibilityIdentifier("metronome.accentFirstBeat")

                        Stepper(value: $model.metronome.countInBeats, in: 0...16, step: 1) {
                            HStack {
                                Text("Count-in")
                                Spacer()
                                Text(verbatim: NativeLocalization.isolate(String(model.metronome.countInBeats)))
                                    .foregroundStyle(BTTheme.muted)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityValue(NativeLocalization.isolate(String(model.metronome.countInBeats)))
                        .accessibilityIdentifier("metronome.countIn")
                    }
                    .padding(.top, BTSpacing.sm)
                } label: {
                    Label("Advanced rhythm", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .accessibilityIdentifier("metronome.advancedRhythm")
                }
                .tint(BTTheme.accent)
                .accessibilityValue(Text(verbatim: NativeLocalization.string(advancedRhythmExpanded ? "Expanded" : "Collapsed")))
                .accessibilityHint(Text(verbatim: NativeLocalization.string("Advanced rhythm")))
            }

            MetronomePresetsCard()
        }
        .navigationTitle("Metronome")
        .accessibilityIdentifier("screen.metronome")
    }
}

struct ScorePracticeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importError: String?
    @AccessibilityFocusState private var importErrorFocused: Bool

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Sheet music",
                title: "Score Practice",
                subtitle: "Keep your music and practice notes together."
            )

            BTCard {
                BTSectionHeader(title: "Add sheet music", subtitle: "Add sheet music from Files or Photos.")
                HStack(spacing: BTSpacing.md) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("score.import.files")

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Photos", systemImage: "photo")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("score.import.photos")

                    if NativeTestFixtures.areEnabled {
                        Button {
                            model.importSampleScore()
                        } label: {
                            Label("Test score", systemImage: "music.note")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("score.import.testFixture")
                    }
                }

                if let importError {
                    Text(verbatim: importError)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BTTheme.danger)
                        .accessibilityFocused($importErrorFocused)
                        .accessibilityIdentifier("score.import.error")
                }
            }

            if model.scores.isEmpty {
                BTEmptyState(title: "No sheet music yet", message: "Add a PDF or photo when you are ready to practice from a score.", systemImage: "doc.viewfinder")
                    .accessibilityIdentifier("score.empty")
            } else {
                ForEach(model.scores) { score in
                    ScoreDocumentCard(score: score)
                }
            }
        }
        .navigationTitle("Score Practice")
        .accessibilityIdentifier("screen.scorePractice")
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .heic], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                try model.importScore(from: url)
                importError = nil
            } catch {
                importError = scoreImportFailureMessage(for: error)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self) else { return }
                    try model.importPhotoScore(data: data)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        .onChange(of: importError) { _, message in
            importErrorFocused = message != nil
        }
    }
}

func scoreImportFailureMessage(for error: Error) -> String? {
    if error is CancellationError { return nil }
    let cocoaError = error as NSError
    if cocoaError.domain == NSCocoaErrorDomain,
       cocoaError.code == NSUserCancelledError {
        return nil
    }
    return error.localizedDescription
}

private struct ScoreDocumentCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var showFullPageViewer = false
    @State private var showRename = false
    @State private var showGuidedPractice = false
    @State private var scoreGuidedRun: ScoreGuidedPracticeRun?
    @State private var renameTitle = ""
    let score: ImportedScore

    var body: some View {
        BTCard(tint: score.id == model.activeScoreID ? BTTheme.surfaceWarm : BTTheme.surface) {
            HStack(alignment: .top, spacing: BTSpacing.md) {
                Button {
                    showFullPageViewer = true
                } label: {
                    ScoreThumbnailView(page: score.selectedPage)
                        .frame(width: 98, height: 132)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BTTheme.text)
                                .padding(5)
                                .background(BTTheme.surface.opacity(0.72), in: Circle())
                                .padding(6)
                                .accessibilityHidden(true)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("score.viewFullPage.thumbnail")
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(verbatim: score.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BTTheme.text)
                        .accessibilityIdentifier("score.card")
                    Text(verbatim: NativeLocalization.format(
                        "%@ • %@",
                        score.sourceKind.title,
                        score.pageCountLabel
                    ))
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    if let composer = score.composer {
                        Text(verbatim: composer)
                            .font(.caption)
                            .foregroundStyle(BTTheme.muted)
                    }
                }
                Spacer()
                BTStatusPill(text: score.id == model.activeScoreID ? "Active" : "Local", tint: score.id == model.activeScoreID ? BTTheme.success : BTTheme.blue)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BTSpacing.sm) {
                    ForEach(score.pages) { page in
                        Button {
                            model.selectScorePage(scoreID: score.id, pageID: page.id)
                        } label: {
                            HStack(spacing: BTSpacing.xs) {
                                Text(verbatim: NativeLocalization.format("Page %@", String(page.pageNumber)))
                                if page.id == score.selectedPage?.id {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, BTSpacing.sm)
                            .frame(minHeight: 44)
                            .background(page.id == score.selectedPage?.id ? BTTheme.accent.opacity(0.22) : BTTheme.surfaceAlt, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page.id == score.selectedPage?.id ? .isSelected : [])
                        .accessibilityIdentifier("score.page.\(page.pageNumber)")
                    }
                }
            }

            if let page = score.selectedPage {
                ScorePageControls(scoreID: score.id, page: page)
            }

            ScoreAnnotationEditor(score: score)

            Button {
                guard let run = model.startScoreGuidedPractice(scoreID: score.id) else { return }
                scoreGuidedRun = run
                showGuidedPractice = true
            } label: {
                Label("Start guided practice", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("score.startGuidedPractice")

            Text("A manual all-notes routine uses your selected page, tempo target, and practice notes. It does not read or score the notation automatically.")
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showFullPageViewer = true
            } label: {
                Label("View full page", systemImage: "arrow.up.left.and.arrow.down.right.magnifyingglass")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("score.viewFullPage")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: BTSpacing.sm)], spacing: BTSpacing.sm) {
                Button {
                    model.activeScoreID = score.id
                } label: {
                    Label("Use in practice", systemImage: "pin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("score.useInPractice")

                Button {
                    model.attachScoreToLatestSession(scoreID: score.id)
                } label: {
                    Label("Attach to latest", systemImage: "paperclip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .disabled(model.sessions.isEmpty)
                .accessibilityIdentifier("score.attachLatest")
            }

            Menu {
                Button {
                    renameTitle = score.title
                    showRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .accessibilityIdentifier("score.rename")

                ShareLink(item: score.exportText) {
                    Label("Export metadata", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("score.export")

                if let fileURL = model.storedScoreFileURL(for: score) {
                    ShareLink(item: fileURL) {
                        Label("Share original file", systemImage: "doc")
                    }
                    .accessibilityIdentifier("score.shareFile")
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("score.delete")
            } label: {
                Label("Score actions", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("score.actions")
        }
        .alert("Delete this local score?", isPresented: $confirmDelete) {
            Button("Delete local score", role: .destructive) {
                model.deleteScore(id: score.id)
            }
            Button("Keep score", role: .cancel) {}
        } message: {
            Text("This removes the imported file and clears score references from local sessions.")
        }
        .alert("Rename score", isPresented: $showRename) {
            TextField("Score title", text: $renameTitle)
                .accessibilityIdentifier("score.rename.title")
            Button("Rename") {
                _ = model.renameScore(id: score.id, title: renameTitle)
            }
            .disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameTitle.count > 120)
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showFullPageViewer) {
            ScorePageViewerView(score: score)
        }
        .fullScreenCover(isPresented: $showGuidedPractice) {
            if let scoreGuidedRun {
                ScoreGuidedPracticeView(score: score, run: scoreGuidedRun)
            }
        }
    }
}

private struct ScoreThumbnailView: View {
    @State private var thumbnailImage: UIImage?
    let page: ScorePage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BTTheme.surfaceAlt)
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scoreEnhancement(page?.enhancement ?? .original)
                    .scaleEffect(cropScale)
                    .offset(y: cropOffsetY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .rotationEffect(.degrees(Double(page?.rotationDegrees ?? 0)))
            } else {
                Image(systemName: "doc.text.image")
                    .font(.title)
                    .foregroundStyle(BTTheme.blue)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BTTheme.panelLine, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(Text(verbatim: page.map {
            NativeLocalization.format("Score page %@ preview", String($0.pageNumber))
        } ?? NativeLocalization.string("Score page preview")))
        .task(id: page?.id) {
            thumbnailImage = page?.thumbnailPNGData.flatMap(UIImage.init(data:))
        }
    }

    private var cropScale: CGFloat {
        switch page?.cropPreset ?? .fullPage {
        case .fullPage: return 1
        case .trimMargins: return 1.16
        case .upperHalf, .lowerHalf: return 1.82
        }
    }

    private var cropOffsetY: CGFloat {
        switch page?.cropPreset ?? .fullPage {
        case .fullPage, .trimMargins: return 0
        case .upperHalf: return 56
        case .lowerHalf: return -56
        }
    }
}

private extension View {
    @ViewBuilder
    func scoreEnhancement(_ enhancement: ScoreEnhancement) -> some View {
        switch enhancement {
        case .original:
            self
        case .grayscale:
            self.saturation(0)
        case .contrast:
            self.contrast(1.28).brightness(0.03)
        case .highContrast:
            self.saturation(0).contrast(1.85).brightness(0.05)
        }
    }
}

// MARK: - Full-resolution page viewer

/// Full-screen, zoomable viewer for an imported score page. Reads the
/// full-resolution original from disk (PDF via PDFKit, image via ImageIO
/// downsampling) and falls back to the stored page thumbnail when the original
/// file is unavailable (e.g. the synthetic sample score, whose localFileName is
/// nil). This is real viewing only — no OCR/analysis or score-following.
private struct ScorePageViewerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let score: ImportedScore
    @State private var pageIndex: Int

    init(score: ImportedScore) {
        self.score = score
        let selectedID = score.selectedPageID ?? score.pages.first?.id
        _pageIndex = State(initialValue: score.pages.firstIndex { $0.id == selectedID } ?? 0)
    }

    private var currentPage: ScorePage? {
        guard score.pages.indices.contains(pageIndex) else { return score.pages.first }
        return score.pages[pageIndex]
    }

    private var isPDF: Bool { score.sourceKind == .filesPDF }

    private var showsImagePager: Bool { !isPDF && score.pages.count > 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if isPDF, let url = model.storedScoreFileURL(for: score), let document = PDFDocument(url: url) {
                    ScorePDFKitView(document: document, initialPageIndex: pageIndex)
                        .ignoresSafeArea(edges: .bottom)
                } else if let page = currentPage {
                    ScoreImagePageView(score: score, page: page)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    unavailableView
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if showsImagePager {
                    pager
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: BTSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: score.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityIdentifier("score.fullPageViewer")
                Text(verbatim: isPDF
                    ? NativeLocalization.isolate(score.pageCountLabel)
                    : NativeLocalization.format(
                        "Page %@ of %@",
                        String(currentPage?.pageNumber ?? pageIndex + 1),
                        String(score.pages.count)
                    ))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
            }
            Spacer(minLength: BTSpacing.md)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.vertical, BTSpacing.sm)
            }
            .accessibilityIdentifier("score.viewer.done")
        }
        .padding(BTSpacing.md)
        .brassGlass(cornerRadius: 0)
    }

    private var pager: some View {
        HStack(spacing: BTSpacing.xl) {
            Button {
                pageIndex = max(0, pageIndex - 1)
            } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.bold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(pageIndex <= 0)
            .accessibilityLabel(Text(verbatim: NativeLocalization.string("Previous")))
            .accessibilityIdentifier("score.viewer.previousPage")

            Text(verbatim: NativeLocalization.isolate("\(currentPage?.pageNumber ?? pageIndex + 1) / \(score.pages.count)"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()

            Button {
                pageIndex = min(score.pages.count - 1, pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.bold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(pageIndex >= score.pages.count - 1)
            .accessibilityLabel(Text(verbatim: NativeLocalization.string("Next")))
            .accessibilityIdentifier("score.viewer.nextPage")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, BTSpacing.xl)
        .padding(.vertical, BTSpacing.md)
        .btContentSurface(cornerRadius: BTTheme.radius, tint: Color.black.opacity(0.72), interactive: true)
        .padding(.bottom, BTSpacing.xl)
    }

    private var unavailableView: some View {
        VStack(spacing: BTSpacing.md) {
            Image(systemName: "doc.text.image")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.72))
            Text("The full-resolution page is unavailable on this device.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
        }
        .padding(BTSpacing.xl)
        .accessibilityIdentifier("score.viewer.unavailable")
    }
}

/// Loads and shows a single image page in a zoomable container. Uses ImageIO
/// downsampling (capped, memory-safe) on the full-resolution original, falling
/// back to the stored thumbnail when the original file is missing.
private struct ScoreImagePageView: View {
    @EnvironmentObject private var model: AppModel
    let score: ImportedScore
    let page: ScorePage
    @State private var image: UIImage?
    @State private var didFinishLoading = false

    var body: some View {
        Group {
            if let image {
                ScoreZoomableImageView(image: image)
                    .scoreEnhancement(page.enhancement)
            } else if didFinishLoading {
                VStack(spacing: BTSpacing.md) {
                    Image(systemName: "doc.text.image")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.72))
                    Text("The full-resolution page is unavailable on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                }
                .padding(BTSpacing.xl)
                .accessibilityIdentifier("score.viewer.unavailable")
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: page.id) {
            didFinishLoading = false
            let storedURL = model.storedScoreFileURL(for: score)
            let target = ScoreImageLoader.viewerMaxPixelSize()
            let thumbnailData = page.thumbnailPNGData
            let rotation = page.rotationDegrees
            let loaded = await Task.detached(priority: .userInitiated) {
                let base = storedURL.flatMap { ScoreImageLoader.downsampledImage(at: $0, maxPixelSize: target) }
                    ?? thumbnailData.flatMap(UIImage.init(data:))
                return base?.bt_rotated(byDegrees: rotation)
            }.value
            image = loaded
            didFinishLoading = true
        }
    }
}

/// UIScrollView-backed pinch/double-tap zoom container for a single UIImage.
private struct ScoreZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(1, animated: false)
        }
        context.coordinator.layout(scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
        }

        func layout(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }
            if scrollView.zoomScale == 1 {
                imageView.frame = CGRect(origin: .zero, size: bounds)
                scrollView.contentSize = bounds
            }
            centerContent(scrollView)
        }

        private func centerContent(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let targetScale = min(scrollView.maximumZoomScale, 3)
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / targetScale, height: scrollView.bounds.height / targetScale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// PDFKit-backed page viewer. PDFView provides pinch-zoom and paging for free.
private struct ScorePDFKitView: UIViewRepresentable {
    let document: PDFDocument
    let initialPageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .clear
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.maxScaleFactor = 6
        pdfView.document = document
        if document.pageCount > 0 {
            let index = max(0, min(initialPageIndex, document.pageCount - 1))
            if let page = document.page(at: index) {
                DispatchQueue.main.async {
                    pdfView.go(to: page)
                }
            }
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {}
}

/// Memory-safe image decoding helpers for the full-page viewer.
private enum ScoreImageLoader {
    /// Longest-edge pixel cap for the decoded viewer image. Generous enough for
    /// crisp zooming but bounded so a high-megapixel scan never expands into an
    /// oversized bitmap in memory.
    @MainActor
    static func viewerMaxPixelSize() -> CGFloat {
        let screen = UIScreen.main
        let longestEdgePixels = max(screen.bounds.width, screen.bounds.height) * screen.scale
        return max(3000, longestEdgePixels)
    }

    static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
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
}

private extension UIImage {
    /// Applies a 0/90/180/270 rotation cheaply via image orientation (no redraw).
    func bt_rotated(byDegrees degrees: Int) -> UIImage {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0, let cgImage else { return self }
        let orientation: UIImage.Orientation
        switch normalized {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: return self
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }
}

private struct ScorePageControls: View {
    @EnvironmentObject private var model: AppModel
    let scoreID: ImportedScore.ID
    let page: ScorePage

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            BTSectionHeader(title: "Page cleanup", subtitle: "Rotate, crop, and enhance the practice preview. Original file remains local.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: BTSpacing.sm)], spacing: BTSpacing.sm) {
                Button {
                    model.rotateSelectedScorePage(scoreID: scoreID)
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("score.rotate")

                Picker("Crop", selection: Binding(get: { page.cropPreset }, set: { model.setSelectedScorePageCrop(scoreID: scoreID, crop: $0) })) {
                    ForEach(ScoreCropPreset.allCases) { preset in
                        Text(verbatim: preset.title).tag(preset)
                    }
                }
                .accessibilityIdentifier("score.crop")
            }

            Picker("Enhance", selection: Binding(get: { page.enhancement }, set: { model.setSelectedScorePageEnhancement(scoreID: scoreID, enhancement: $0) })) {
                ForEach(ScoreEnhancement.allCases) { enhancement in
                    Text(verbatim: enhancement.title).tag(enhancement)
                }
            }
            .accessibilityIdentifier("score.enhance")

        }
        .padding(BTSpacing.md)
        .btContentSurface(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt)
    }
}

private struct ScoreAnnotationEditor: View {
    @EnvironmentObject private var model: AppModel
    let score: ImportedScore

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            BTSectionHeader(title: "Practice notes", subtitle: "Jot notes for the tricky spots.")
            TextField("Focus measures", text: Binding(get: { score.annotation.focusMeasures }, set: { model.updateScoreAnnotation(scoreID: score.id, focusMeasures: $0) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("score.focusMeasures")
            TextField("Problem passage", text: Binding(get: { score.annotation.problemPassage }, set: { model.updateScoreAnnotation(scoreID: score.id, problemPassage: $0) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("score.problemPassage")
            Stepper(value: Binding(get: { score.annotation.tempoTarget }, set: { model.updateScoreAnnotation(scoreID: score.id, tempoTarget: $0) }), in: 30...240, step: 2) {
                Text(verbatim: NativeLocalization.format("Tempo target: %@ BPM", String(score.annotation.tempoTarget)))
            }
                .accessibilityIdentifier("score.tempoTarget")
            TextField("Practice notes", text: Binding(get: { score.annotation.notes }, set: { model.updateScoreAnnotation(scoreID: score.id, notes: $0) }), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("score.notes")
        }
        .padding(BTSpacing.md)
        .btContentSurface(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt)
    }
}

/// A deliberately manual score routine. Imported PDFs and photos remain
/// viewable practice material; BrassTune does not claim OCR, score following,
/// or automatic note/rhythm grading for them.
private struct ScoreGuidedPracticeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let score: ImportedScore
    let run: ScoreGuidedPracticeRun

    @State private var phase: ScoreGuidedPracticePhase = .ready
    @State private var startedAt: Date?
    @State private var timer = ScoreGuidedPracticeTimerState()
    @State private var timerNow = Date()
    @State private var completionSaved = false
    @State private var currentNoteIndex = 0

    private let writtenNoteRoutine = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    var body: some View {
        NavigationStack {
            BTScreen {
                BTPageHeader(
                    eyebrow: "Manual routine",
                    title: "Guided score practice",
                    subtitle: .verbatim("All notes at \(run.configuration.tempoBPM) BPM — follow your score and mark your own progress.")
                )

                if phase == .ready {
                    Button { begin() } label: {
                        Label("Begin routine", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("score.guided.begin")
                } else if phase == .running {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BTSpacing.sm) {
                        Button {
                            timer.pause(at: Date())
                            timerNow = Date()
                            phase = .paused
                        } label: {
                            Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("score.guided.pause")
                        Button { finish() } label: {
                            Label("Finish", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTPrimaryButtonStyle())
                        .disabled(activeDuration < 1)
                        .accessibilityIdentifier("score.guided.finish")
                    }
                } else if phase == .paused {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BTSpacing.sm) {
                        Button {
                            timer.resume(at: Date())
                            timerNow = Date()
                            phase = .running
                        } label: {
                            Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTPrimaryButtonStyle())
                        .accessibilityIdentifier("score.guided.resume")
                        Button { finish() } label: {
                            Label("Finish", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .disabled(activeDuration < 1)
                    }
                }

                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(title: .verbatim(score.title), subtitle: .verbatim("Selected score page \(run.configuration.pageNumber)"))
                    Text("All notes")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BTTheme.text)
                    Text("Chromatic written-note check-in. This is a manual cue sequence, not automatic score following or performance scoring.")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: BTSpacing.sm)], spacing: BTSpacing.sm) {
                        ForEach(writtenNoteRoutine, id: \.self) { note in
                            let isCurrent = writtenNoteRoutine[currentNoteIndex] == note
                            Text(verbatim: NativeLocalization.preserve(note))
                                .font(.headline.monospaced())
                                .foregroundStyle(isCurrent ? BTTheme.text : BTTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isCurrent ? BTTheme.accent.opacity(0.28) : BTTheme.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        }
                    }
                    .accessibilityIdentifier("score.guided.allNotes")

                    if phase == .running || phase == .paused {
                        Text(verbatim: NativeLocalization.format("Current note %@", NativeLocalization.preserve(writtenNoteRoutine[currentNoteIndex])))
                            .font(.headline)
                            .foregroundStyle(BTTheme.text)
                            .accessibilityIdentifier("score.guided.currentNote")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BTSpacing.sm) {
                            Button { currentNoteIndex = max(0, currentNoteIndex - 1) } label: {
                                Label("Previous note", systemImage: "chevron.left").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BTSecondaryButtonStyle())
                            .disabled(currentNoteIndex == 0)
                            .accessibilityIdentifier("score.guided.previousNote")
                            Button { currentNoteIndex = min(writtenNoteRoutine.count - 1, currentNoteIndex + 1) } label: {
                                Label("Next note", systemImage: "chevron.right").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BTSecondaryButtonStyle())
                            .disabled(currentNoteIndex == writtenNoteRoutine.count - 1)
                            .accessibilityIdentifier("score.guided.nextNote")
                        }
                    }
                }

                BTCard {
                    HStack {
                        Label("Elapsed", systemImage: "timer")
                        Spacer()
                        Text(verbatim: NativeLocalization.isolate(elapsedTimeText))
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(BTTheme.text)
                    .accessibilityIdentifier("score.guided.elapsed")

                    if !run.configuration.focusMeasures.isEmpty || !run.configuration.problemPassage.isEmpty || !run.configuration.practiceNotes.isEmpty {
                        Divider()
                        if !run.configuration.focusMeasures.isEmpty { guidedDetail("Focus", run.configuration.focusMeasures) }
                        if !run.configuration.problemPassage.isEmpty { guidedDetail("Passage", run.configuration.problemPassage) }
                        if !run.configuration.practiceNotes.isEmpty { guidedDetail("Notes", run.configuration.practiceNotes) }
                    }
                }

                switch phase {
                case .ready:
                    EmptyView()
                case .running:
                    EmptyView()
                case .paused:
                    EmptyView()
                case .completed:
                    BTCard(tint: BTTheme.surfaceWarm) {
                        Label {
                            Text(verbatim: NativeLocalization.string(completionSaved ? "Practice saved" : "Practice finished"))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                            .font(.headline)
                            .foregroundStyle(BTTheme.success)
                    }
                    Button("Done") { dismiss() }
                        .buttonStyle(BTPrimaryButtonStyle())
                        .accessibilityIdentifier("score.guided.done")
                }

                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("score.guided.cancel")
            }
            .navigationTitle("Guided practice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task(id: phase) {
            while phase == .running && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard phase == .running else { break }
                timerNow = Date()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard phase == .running, newPhase != .active else { return }
            timer.pause(at: Date())
            timerNow = Date()
            phase = .paused
        }
    }

    private var elapsedTimeText: String {
        let wholeSeconds = Int(activeDuration.rounded(.down))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    private var activeDuration: TimeInterval { timer.activeDuration(at: timerNow) }

    private func guidedDetail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: NativeLocalization.string(label)).font(.caption.weight(.bold)).foregroundStyle(BTTheme.muted)
            Text(verbatim: value).font(.subheadline).foregroundStyle(BTTheme.text)
        }
    }

    private func begin() {
        startedAt = Date()
        timer.start(at: startedAt ?? Date())
        timerNow = startedAt ?? Date()
        phase = .running
    }

    private func finish() {
        let completedAt = Date()
        let duration = timer.finish(at: completedAt)
        timerNow = completedAt
        guard duration >= 1 else { return }
        let activeStart = startedAt ?? Date()
        let completion = ScoreGuidedPracticeCompletion(
            activityInstanceID: run.activityInstanceID,
            configuration: run.configuration,
            startedAt: activeStart,
            completedAt: completedAt,
            activeDurationSeconds: duration
        )
        completionSaved = model.saveScoreGuidedPracticeCompletion(completion)
        phase = .completed
    }
}

private enum ScoreGuidedPracticePhase: Equatable {
    case ready
    case running
    case paused
    case completed
}

@ViewBuilder
func instrumentPickerOptions() -> some View {
    Text(verbatim: NativeLocalization.string("Trumpet in B♭")).tag("trumpet")
    Text(verbatim: NativeLocalization.string("Horn in F")).tag("horn")
    Text(verbatim: NativeLocalization.string("Trombone")).tag("trombone")
    Text(verbatim: NativeLocalization.string("Euphonium")).tag("euphonium")
    Text(verbatim: NativeLocalization.string("Tuba")).tag("tuba")
}
