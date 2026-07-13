import ImageIO
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case playAlong
    case tuner
    case progress
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playAlong: return "Play-Along"
        case .tuner: return "Tuner"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .playAlong: return "music.note.list"
        case .tuner: return "tuningfork"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .playAlong
    @State private var onboardingPresented: Bool
    private let resetUITestState: Bool
    private let settingsOnlyLaunch: Bool
    private let uiTestMode: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        settingsOnlyLaunch = arguments.contains("UITEST_SETTINGS")
        resetUITestState = arguments.contains("UITEST_RESET_STATE")
        uiTestMode = arguments.contains("UITEST_DEMO")
            || arguments.contains("UITEST_FIXTURES")
            || arguments.contains("UITEST_SETTINGS")
        _onboardingPresented = State(initialValue: !uiTestMode)
    }

    var body: some View {
        Group {
            if settingsOnlyLaunch {
                NavigationStack {
                    SettingsView(onboardingPresented: $onboardingPresented)
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        PlayAlongView()
                    }
                    .tabItem {
                        Label(AppTab.playAlong.title, systemImage: AppTab.playAlong.systemImage)
                    }
                    .tag(AppTab.playAlong)

                    NavigationStack {
                        TunerView()
                    }
                    .tabItem {
                        Label(AppTab.tuner.title, systemImage: AppTab.tuner.systemImage)
                    }
                    .tag(AppTab.tuner)

                    NavigationStack {
                        ProgressTabView(selectedTab: $selectedTab)
                    }
                    .tabItem {
                        Label(AppTab.progress.title, systemImage: AppTab.progress.systemImage)
                    }
                    .tag(AppTab.progress)

                    NavigationStack {
                        SettingsView(onboardingPresented: $onboardingPresented)
                    }
                    .tabItem {
                        Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                    }
                    .tag(AppTab.settings)
                }
                .tint(BTTheme.accent)
                .onChange(of: selectedTab) { oldTab, newTab in
                    if oldTab == .playAlong,
                       newTab != .playAlong,
                       model.playAlongPhase == .running || model.playAlongStartInProgress {
                        model.stopPlayAlong()
                    }
                    if oldTab == .tuner, newTab != .tuner {
                        model.cancelRecordingStart()
                        if model.audioEngine.recording {
                            model.stopRecording()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $onboardingPresented) {
            OnboardingView(isPresented: $onboardingPresented, selectedTab: $selectedTab)
        }
        .task {
            if resetUITestState {
                model.resetForUITesting()
            }
            guard !uiTestMode else { return }
            await model.restoreSession()
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            BTScreen {
                BTPageHeader(
                    eyebrow: "BrassTune",
                    title: "Choose your instrument",
                    subtitle: "Pick your instrument so tuning matches your horn."
                )
                .accessibilityIdentifier("onboarding.hero")

                BTCard {
                    Picker("Instrument", selection: $model.selectedInstrumentId) {
                        instrumentPickerOptions()
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("onboarding.instrumentPicker")
                }

                Button {
                    model.enterGuestDemo()
                    selectedTab = .playAlong
                    isPresented = false
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                .accessibilityIdentifier("onboarding.startPractice")
            }
            .navigationTitle("Welcome")
        }
        // Open at full height so the primary "Start" action is always visible
        // (at .medium it fell below the fold on smaller devices).
        .presentationDetents([.large])
    }
}

struct PlayAlongView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "BrassTune",
                title: "Play-Along",
                subtitle: "Choose an exercise, play each highlighted note, and hold it steady."
            )
            .accessibilityIdentifier("playAlong.hero")

            switch model.playAlongPhase {
            case .idle:
                exercisePicker
                startButton
                microphoneRecovery
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
        .safeAreaInset(edge: .bottom) {
            if model.playAlongPhase == .running {
                PlayAlongTransportBar()
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.bottom, BTSpacing.md)
            }
        }
        .navigationTitle("Play-Along")
        .accessibilityIdentifier("screen.playAlong")
    }

    private var exercisePicker: some View {
        BTCard {
            BTSectionHeader(title: "Choose an exercise", subtitle: "C major is a friendly place to start.")
            Picker("Exercise", selection: $model.selectedPlayAlongExerciseID) {
                ForEach(PlayAlongExerciseCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(model.playAlongExercises.filter { $0.category == category }) { exercise in
                            Text(exercise.title)
                                .tag(exercise.id)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("playAlong.exercisePicker")

            let exercise = model.selectedPlayAlongExercise
            Text(exercise.detail)
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BTSpacing.sm) {
                    ForEach(Array(exercise.writtenNotes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.headline.monospaced())
                            .padding(.horizontal, BTSpacing.md)
                            .padding(.vertical, BTSpacing.sm)
                            .background(BTTheme.surfaceAlt, in: Capsule())
                    }
                }
            }
            .accessibilityIdentifier("playAlong.exerciseNotes")
        }
    }

    private var startButton: some View {
        Button {
            Task {
                await model.startPlayAlong(exerciseID: model.selectedPlayAlongExerciseID)
            }
        } label: {
            Label(model.playAlongStartInProgress ? "Getting ready…" : "Start listening", systemImage: "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
        .disabled(model.playAlongStartInProgress)
        .accessibilityIdentifier("playAlong.start")
    }

    @ViewBuilder
    private var microphoneRecovery: some View {
        if model.audioEngine.permissionDenied {
            MicrophoneRecoveryView()
        } else if let error = model.lastError {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(BTTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playAlong.error")
        } else {
            Text("Your first tap asks for microphone access.")
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
        }
    }
}

private struct PlayAlongLiveView: View {
    let session: PlayAlongSession

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            Text("Note \(min(session.currentNoteIndex + 1, session.exercise.writtenNotes.count)) of \(session.exercise.writtenNotes.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BTTheme.muted)

            Text(session.currentNoteName ?? "—")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(BTTheme.accent)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("playAlong.targetNote")

            Text("Hold steady")
                .font(.headline)
                .frame(maxWidth: .infinity)

            ProgressView(value: session.heldFraction)
                .tint(BTTheme.success)
                .accessibilityLabel("Hold progress")
                .accessibilityValue("\(Int((session.heldFraction * 100).rounded())) percent")
                .accessibilityIdentifier("playAlong.holdProgress")

            VStack(spacing: BTSpacing.xs) {
                Text(session.detectedNoteName.map { "You're playing \($0)" } ?? "Listening…")
                    .font(.title3.weight(.semibold))
                Text(playAlongFeedback(session))
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
    }
}

private struct PlayAlongSequenceView: View {
    let session: PlayAlongSession

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
                        Text(note)
                            .font(.headline.monospaced())
                            .foregroundStyle(tint)
                            .frame(width: 44, height: 44)
                            .background(tint.opacity(active || completed ? 0.15 : 0.06), in: Circle())
                            .overlay {
                                Circle().stroke(tint.opacity(active ? 0.75 : 0.25), lineWidth: active ? 2 : 1)
                            }
                            .accessibilityLabel("\(note), \(completed ? session.noteGrades[index].rating.title : (active ? "current note" : "up next"))")
                    }
                }
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
            BTSectionHeader(title: "Your score", subtitle: exercise.title)

            Text("\(grade.inTunePercentage)%")
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
            .accessibilityLabel("\(grade.stars) out of 3 stars")

            Text(playAlongScoreMessage(grade))
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: BTSpacing.md) {
                BTMetricTile(
                    title: "Notes played",
                    value: "\(grade.notesPlayed)/\(grade.totalNotes)",
                    detail: "completed"
                )
                BTMetricTile(
                    title: "Average",
                    value: grade.averageAbsoluteCents.map { String(format: "%.1f", $0) } ?? "—",
                    detail: "cents from center",
                    tint: BTTheme.secondaryAccent
                )
            }
        }

        BTCard {
            BTSectionHeader(title: "Note by note", subtitle: "Cents show the small distance from the center of a note.")
            ForEach(grade.noteGrades) { noteGrade in
                HStack {
                    Text(noteGrade.writtenNoteName)
                        .font(.headline.monospaced())
                    Spacer()
                    Text(noteGrade.medianCents.map { String(format: "%+.1f cents", $0) } ?? "Skipped")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(playAlongRatingTint(noteGrade.rating))
                    Text(noteGrade.rating.title)
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
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playAlong.skip")

            Divider()
                .frame(height: 24)

            Button(role: .destructive) {
                model.stopPlayAlong()
            } label: {
                Label("Stop", systemImage: "stop.fill")
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

    private var activeFrame: PitchFrame? {
        guard audioEngine.recording else { return nil }
        guard audioEngine.activeSource == .live || model.testFixturesEnabled else { return nil }
        return audioEngine.currentFrame
    }

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Tuner",
                title: "Find the center",
                subtitle: "Play a note and BrassTune will show whether it is flat, in tune, or sharp."
            )

            TunerReadout(frame: activeFrame)

            if !audioEngine.recording {
                Button {
                    Task {
                        await model.startRecording()
                    }
                } label: {
                    Label("Start listening", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrassGlassButtonStyle(prominent: true, tint: BTTheme.accent))
                .disabled(model.recordingStartInProgress)
                .accessibilityIdentifier("tuner.recordButton")
            }

            if audioEngine.permissionDenied {
                MicrophoneRecoveryView()
            } else if let notice = audioEngine.audioNotice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tuner.audioNotice")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if audioEngine.recording {
                FloatingPracticeControlBar()
                    .padding(.horizontal, BTSpacing.lg)
                    .padding(.bottom, BTSpacing.md)
            }
        }
        .navigationTitle("Tuner")
        .accessibilityIdentifier("screen.tuner")
    }
}

private struct TunerReadout: View {
    let frame: PitchFrame?

    private var noteLabel: String {
        guard let note = frame?.writtenNoteName else { return "Play a note" }
        return "\(note)\(frame?.writtenOctave.map(String.init) ?? "")"
    }

    private var verdict: String {
        guard let frame else { return "Listening…" }
        switch frame.tuningStatus {
        case .inTune: return "In tune — hold it steady"
        case .sharp: return "A little sharp — ease down"
        case .flat: return "A little flat — lift up"
        case .silence, .noLock, .unstable: return "Listening…"
        }
    }

    private var tint: Color {
        guard let frame else { return BTTheme.muted }
        switch frame.tuningStatus {
        case .inTune: return BTTheme.success
        case .sharp: return BTTheme.sharp
        case .flat: return BTTheme.flat
        case .silence, .noLock, .unstable: return BTTheme.muted
        }
    }

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            Text(noteLabel)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.65)
                .accessibilityIdentifier("tuner.note")

            Text(verdict)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("tuner.verdict")

            TuningMeter(cents: frame?.centsDeviation)
        }
    }
}

private struct TuningMeter: View {
    let cents: Double?

    private var clampedCents: Double {
        min(50, max(-50, cents ?? 0))
    }

    private var accessibilityVerdict: String {
        guard let cents else { return "Waiting for a note" }
        if abs(cents) <= 5 { return "In tune" }
        return cents > 0 ? "Sharp" : "Flat"
    }

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            GeometryReader { proxy in
                let travel = max(0, proxy.size.width / 2 - 5)
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
                        .offset(x: CGFloat(clampedCents / 50) * travel)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 40)

            HStack {
                Label("Flat", systemImage: "arrow.down")
                    .foregroundStyle(BTTheme.flat)
                Spacer()
                Text("In tune")
                    .foregroundStyle(BTTheme.success)
                Spacer()
                Label("Sharp", systemImage: "arrow.up")
                    .foregroundStyle(BTTheme.sharp)
            }
            .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tuning meter")
        .accessibilityValue(accessibilityVerdict)
        .accessibilityIdentifier("tuner.meter")
    }
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
                .accessibilityLabel("Stop and save recording")
                .accessibilityIdentifier("tuner.floating.stop")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.danger))

                Button {
                    model.toggleMetronome()
                } label: {
                    Label(
                        model.metronomeRunning ? "Stop metronome" : "Start metronome",
                        systemImage: model.metronomeRunning ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                }
                .accessibilityLabel(model.metronomeRunning ? "Stop metronome" : "Start metronome")
                .accessibilityIdentifier("tuner.floating.metronome")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.warning))

                VStack(spacing: 0) {
                    Text("\(model.metronome.bpm)")
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
                .accessibilityLabel("Decrease tempo")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))

                Button {
                    model.adjustTempo(by: 2)
                } label: {
                    Label("Tempo up", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Increase tempo")
                .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))
            }

            Text(model.metronomeRunning ? "Visual beat while recording" : "Recording")
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

private struct MicrophoneRecoveryView: View {
    var body: some View {
        BTCard {
            BTSectionHeader(
                title: "Microphone access is off",
                subtitle: "Allow microphone access in iOS Settings, then come back and try again."
            )
            Button {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "gearshape")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("microphone.openSettings")
        }
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
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(BTTheme.text)
                        .accessibilityIdentifier("sessions.sessionName")
                    Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(instrumentDisplayName(session.instrumentId))")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }
                Spacer()
                Text("\(Int(session.inTunePercentage.rounded()))% in tune")
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
                        title: session.name,
                        subtitle: session.startedAt.formatted(date: .complete, time: .shortened)
                    )
                    Text("\(Int(session.inTunePercentage.rounded()))%")
                        .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                        .accessibilityIdentifier("session.score")
                    Text(session.inTunePercentage >= 70
                        ? "You found the center often. Keep building that steady sound."
                        : "Slow down and hold each note steady before moving on.")
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
                            value: String(format: "%.1f", session.averageAbsCents),
                            detail: "cents"
                        )
                        BTMetricTile(
                            title: "In tune",
                            value: "\(Int(session.inTunePercentage.rounded()))%",
                            detail: "within 5 cents",
                            tint: BTTheme.success
                        )
                    }
                    Text("Notes heard: \(session.pitchCoverageLabel)")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }

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
    }
}

struct ProgressTabView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        let snapshot = model.analyticsSnapshot
        BTScreen {
            if snapshot.hasSessions {
                BTPageHeader(
                    eyebrow: "Progress",
                    title: "Your progress",
                    subtitle: "See how your tuning changes as you practice."
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145), spacing: BTSpacing.md)],
                    spacing: BTSpacing.md
                ) {
                    BTMetricTile(
                        title: "In tune",
                        value: "\(Int(snapshot.averageInTunePercentage.rounded()))%",
                        detail: "within 5 cents",
                        tint: BTTheme.success
                    )
                    BTMetricTile(
                        title: "Average distance",
                        value: String(format: "%.1f", snapshot.averageAbsCents),
                        detail: "cents from center",
                        tint: BTTheme.secondaryAccent
                    )
                    BTMetricTile(
                        title: "Practice time",
                        value: practiceTimeLabel(snapshot.totalPracticeSeconds),
                        detail: "saved"
                    )
                    BTMetricTile(
                        title: "Recordings",
                        value: "\(snapshot.sessionCount)",
                        detail: "total"
                    )
                }
                .accessibilityIdentifier("progress.metrics")

                Text("A cent is a very small pitch step. Smaller numbers mean you are closer to the center of the note.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)

                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(title: "Try this next", subtitle: snapshot.recommendation)
                }
                .accessibilityIdentifier("progress.recommendation")

                BTCard {
                    HStack {
                        BTSectionHeader(title: "Practice history", subtitle: "Your latest recordings.")
                        Spacer()
                        NavigationLink {
                            SessionsView()
                        } label: {
                            Text("See all")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("progress.allSessions")
                    }

                    ForEach(model.sessions.prefix(3)) { session in
                        NavigationLink {
                            SessionDetailView(sessionID: session.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                                    Text(session.name)
                                        .font(.headline)
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(BTTheme.muted)
                                }
                                Spacer()
                                Text("\(Int(session.inTunePercentage.rounded()))%")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(session.inTunePercentage >= 70 ? BTTheme.success : BTTheme.warning)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, BTSpacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                BTPageHeader(
                    eyebrow: "Progress",
                    title: "Your progress",
                    subtitle: "Your practice results will appear here."
                )
                BTEmptyState(
                    title: "Ready for your first note?",
                    message: "Start the tuner and save a short recording.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .accessibilityIdentifier("progress.empty")

                Button {
                    selectedTab = .tuner
                } label: {
                    Label("Record your first note", systemImage: "mic.fill")
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("progress.openTuner")
            }
        }
        .navigationTitle("Progress")
        .accessibilityIdentifier("screen.progress")
    }
}

private func playAlongFeedback(_ session: PlayAlongSession) -> String {
    guard let target = session.currentNoteName else { return "Exercise complete" }
    guard session.detectedNoteName == target, let cents = session.detectedCents else {
        return session.detectedNoteName == nil ? "Play \(target)" : "Move to \(target)"
    }
    let rounded = Int(cents.rounded())
    if abs(rounded) <= 5 {
        return "In tune — hold steady"
    }
    return rounded > 0
        ? "\(abs(rounded)) cents sharp — ease down"
        : "\(abs(rounded)) cents flat — lift up"
}

private func playAlongFeedbackTint(_ session: PlayAlongSession) -> Color {
    guard session.detectedNoteName == session.currentNoteName, let cents = session.detectedCents else {
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
    case 3: return "Strong work — try to beat your best."
    case 2: return "Nice start. One more round can make it steadier."
    case 1: return "Keep going. Slow, even air will help."
    default: return "Try again when you're ready."
    }
}

private func practiceTimeLabel(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds.rounded()))s"
    }
    return "\(Int((seconds / 60).rounded()))m"
}
struct MetronomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        Text("\(model.metronome.bpm)")
                            .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(BTTheme.accentSoft)
                            .accessibilityIdentifier("metronome.bpm")
                        Text("\(model.metronome.meterLabel) • \(model.metronome.subdivision.title)")
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
                    Label(model.metronomeRunning ? "Stop metronome" : "Start metronome", systemImage: model.metronomeRunning ? "pause.fill" : "play.fill")
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
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("metronome.tempoDown")

                    Button {
                        model.tapTempo()
                    } label: {
                        Label("Tap tempo", systemImage: "hand.tap")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("metronome.tapTempo")

                    Button {
                        model.adjustTempo(by: 5)
                    } label: {
                        Label("Up", systemImage: "plus")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("metronome.tempoUp")
                }
                Stepper("BPM \(model.metronome.bpm)", value: Binding(get: { model.metronome.bpm }, set: { model.setTempo($0) }), in: 30...240, step: 1)
                    .accessibilityIdentifier("metronome.stepper")
            }

            BTCard {
                BTSectionHeader(title: "Sound and feel", subtitle: "The click is on by default. Use visual-only mode whenever you want silence.")
                Picker("Meter", selection: Binding(get: { model.metronome.beatsPerMeasure }, set: { model.setMeter(beats: $0) })) {
                    ForEach([2, 3, 4, 5, 6, 7, 9, 12], id: \.self) { beats in
                        Text("\(beats)/4").tag(beats)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("metronome.meterPicker")

                Picker("Subdivision", selection: Binding(get: { model.metronome.subdivision }, set: { model.metronome.subdivision = $0 })) {
                    ForEach(MetronomeSubdivision.allCases) { subdivision in
                        Text(subdivision.title).tag(subdivision)
                    }
                }
                .accessibilityIdentifier("metronome.subdivisionPicker")

                Toggle("Visual-only metronome", isOn: Binding(get: { model.metronome.visualOnly }, set: { model.setMetronomeVisualOnly($0) }))
                .accessibilityIdentifier("metronome.visualOnly")
                .accessibilityHint("Visual-only mode gives you a silent beat.")

                Toggle("Haptic pulse", isOn: Binding(get: { model.metronome.hapticsEnabled }, set: { model.metronome.hapticsEnabled = $0 }))
                    .accessibilityIdentifier("metronome.haptics")

                Slider(value: Binding(get: { model.metronome.volume }, set: { model.setMetronomeVolume($0) }), in: 0...1)
                    .disabled(model.metronome.visualOnly)
                    .accessibilityLabel("Metronome volume")
                    .accessibilityIdentifier("metronome.volume")

            }
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
                    Text(importError)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BTTheme.danger)
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
                importError = error.localizedDescription
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
    }
}

private struct ScoreDocumentCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var showFullPageViewer = false
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
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("score.viewFullPage.thumbnail")
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(score.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BTTheme.text)
                    Text("\(score.sourceKind.title) • \(score.pageCountLabel)")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                    if let composer = score.composer {
                        Text(composer)
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
                            Text("Page \(page.pageNumber)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, BTSpacing.sm)
                                .padding(.vertical, BTSpacing.xs)
                                .background(page.id == score.selectedPage?.id ? BTTheme.accent.opacity(0.22) : BTTheme.surfaceAlt, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("score.page.\(page.pageNumber)")
                    }
                }
            }

            if let page = score.selectedPage {
                ScorePageControls(scoreID: score.id, page: page)
            }

            ScoreAnnotationEditor(score: score)

            Button {
                showFullPageViewer = true
            } label: {
                Label("View full page", systemImage: "arrow.up.left.and.arrow.down.right.magnifyingglass")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("score.viewFullPage")

            HStack(spacing: BTSpacing.md) {
                Button {
                    model.activeScoreID = score.id
                } label: {
                    Label("Use in practice", systemImage: "pin")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("score.useInPractice")

                Button {
                    model.attachScoreToLatestSession(scoreID: score.id)
                } label: {
                    Label("Attach to latest", systemImage: "paperclip")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .disabled(model.sessions.isEmpty)
                .accessibilityIdentifier("score.attachLatest")
            }

            HStack(spacing: BTSpacing.md) {
                ShareLink(item: score.exportText) {
                    Label("Export metadata", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("score.export")

                if let fileURL = model.storedScoreFileURL(for: score) {
                    ShareLink(item: fileURL) {
                        Label("Share original file", systemImage: "doc")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("score.shareFile")
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("score.delete")
            }
        }
        .accessibilityIdentifier("score.card")
        .confirmationDialog("Delete this local score?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete local score", role: .destructive) {
                model.deleteScore(id: score.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the imported file and clears score references from local sessions.")
        }
        .fullScreenCover(isPresented: $showFullPageViewer) {
            ScorePageViewerView(score: score)
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
        .accessibilityLabel(page.map { "Score page \($0.pageNumber) preview" } ?? "Score page preview")
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
        .accessibilityIdentifier("score.fullPageViewer")
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: BTSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(score.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(isPDF ? score.pageCountLabel : "Page \(currentPage?.pageNumber ?? pageIndex + 1) of \(score.pages.count)")
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
            }
            .disabled(pageIndex <= 0)
            .accessibilityIdentifier("score.viewer.previousPage")

            Text("\(currentPage?.pageNumber ?? pageIndex + 1) / \(score.pages.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()

            Button {
                pageIndex = min(score.pages.count - 1, pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.bold))
            }
            .disabled(pageIndex >= score.pages.count - 1)
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
                        Text(preset.title).tag(preset)
                    }
                }
                .accessibilityIdentifier("score.crop")
            }

            Picker("Enhance", selection: Binding(get: { page.enhancement }, set: { model.setSelectedScorePageEnhancement(scoreID: scoreID, enhancement: $0) })) {
                ForEach(ScoreEnhancement.allCases) { enhancement in
                    Text(enhancement.title).tag(enhancement)
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
            Stepper("Tempo target \(score.annotation.tempoTarget) BPM", value: Binding(get: { score.annotation.tempoTarget }, set: { model.updateScoreAnnotation(scoreID: score.id, tempoTarget: $0) }), in: 30...240, step: 2)
                .accessibilityIdentifier("score.tempoTarget")
            TextField("Notes", text: Binding(get: { score.annotation.notes }, set: { model.updateScoreAnnotation(scoreID: score.id, notes: $0) }), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("score.notes")
        }
        .padding(BTSpacing.md)
        .btContentSurface(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt)
    }
}

@ViewBuilder
func instrumentPickerOptions() -> some View {
    Text("Trumpet in Bb").tag("trumpet")
    Text("Horn in F").tag("horn")
    Text("Trombone").tag("trombone")
    Text("Euphonium").tag("euphonium")
    Text("Tuba").tag("tuba")
}
