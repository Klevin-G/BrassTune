import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case practice
    case analytics
    case coach
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .practice: return "Practice"
        case .analytics: return "Analytics"
        case .coach: return "Coach"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .practice: return "gauge.with.dots.needle.67percent"
        case .analytics: return "chart.bar.xaxis"
        case .coach: return "sparkles"
        case .more: return "square.grid.2x2"
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .home
    @State private var onboardingPresented: Bool
    private let resetUITestState: Bool
    private let settingsOnlyLaunch: Bool
    private let uiTestMode: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        settingsOnlyLaunch = arguments.contains("UITEST_SETTINGS")
        resetUITestState = arguments.contains("UITEST_RESET_STATE")
        uiTestMode = arguments.contains("UITEST_DEMO") || arguments.contains("UITEST_SETTINGS")
        _onboardingPresented = State(initialValue: !uiTestMode)
    }

    var body: some View {
        Group {
            if settingsOnlyLaunch {
                NavigationStack { SettingsView(onboardingPresented: $onboardingPresented) }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { HomeView(selectedTab: $selectedTab, onboardingPresented: $onboardingPresented) }
                        .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                        .tag(AppTab.home)
                    NavigationStack { PracticeView(selectedTab: $selectedTab) }
                        .tabItem { Label(AppTab.practice.title, systemImage: AppTab.practice.systemImage) }
                        .tag(AppTab.practice)
                    NavigationStack { AnalyticsView(selectedTab: $selectedTab) }
                        .tabItem { Label(AppTab.analytics.title, systemImage: AppTab.analytics.systemImage) }
                        .tag(AppTab.analytics)
                    NavigationStack { CoachNativeView(selectedTab: $selectedTab) }
                        .tabItem { Label(AppTab.coach.title, systemImage: AppTab.coach.systemImage) }
                        .tag(AppTab.coach)
                    NavigationStack { MoreHubView(onboardingPresented: $onboardingPresented, selectedTab: $selectedTab) }
                        .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.systemImage) }
                        .tag(AppTab.more)
                }
                .tint(BTTheme.accent)
                .sheet(isPresented: $onboardingPresented) {
                    OnboardingView(isPresented: $onboardingPresented, selectedTab: $selectedTab)
                }
            }
        }
        .task {
            if resetUITestState {
                model.resetForUITesting()
            }
            if uiTestMode {
                return
            }
            await model.restoreSession()
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab
    @Binding var onboardingPresented: Bool

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Practice cockpit",
                title: "BrassTune",
                subtitle: "A focused brass tuner and local practice log for honest session review.",
                trailing: model.authState.displayTitle
            )
            .accessibilityIdentifier("home.hero")

            Button {
                selectedTab = .practice
            } label: {
                Label("Start practice", systemImage: "play.fill")
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("home.startPractice")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                NavigationLink {
                    MetronomeView()
                } label: {
                    BTInsightTile(title: "Metronome", detail: "\(model.metronome.bpm) BPM, \(model.metronome.meterLabel)", systemImage: "metronome", tint: BTTheme.warning, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.metronome")

                NavigationLink {
                    ScorePracticeView()
                } label: {
                    BTInsightTile(title: "Score Practice", detail: model.activeScore?.title ?? "Import or use sample", systemImage: "doc.viewfinder", tint: BTTheme.blue, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.scorePractice")

                NavigationLink {
                    SettingsView(onboardingPresented: $onboardingPresented)
                } label: {
                    BTInsightTile(title: "Settings", detail: "Horn, pitch, data", systemImage: "gearshape", tint: BTTheme.secondaryAccent, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.settings")
            }

            BTCard(tint: BTTheme.surfaceWarm) {
                BTSectionHeader(title: "Today's intonation focus", subtitle: "Center the note before expanding range.")
                VStack(alignment: .leading, spacing: BTSpacing.md) {
                    Text(model.selectedInstrumentId == "horn" ? "G4" : "D5")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(BTTheme.accentSoft)
                        .minimumScaleFactor(0.7)
                    Text("Slow attacks, steady air, release cleanly. Guest practice stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                    BTMetricTile(title: "Instrument", value: instrumentName(model.selectedInstrumentId), detail: "Written pitch")
                    BTMetricTile(title: "Reference", value: String(format: "%.1f", model.referencePitchHz), detail: "A4 Hz", tint: BTTheme.secondaryAccent)
                    BTMetricTile(title: "Saved", value: "\(model.sessions.count)", detail: "local takes", tint: BTTheme.blue)
                    BTMetricTile(title: "In tune", value: model.analyticsSnapshot.hasSessions ? "\(String(format: "%.0f", model.analyticsSnapshot.averageInTunePercentage))%" : "--", detail: "local frames", tint: BTTheme.success)
                }
            }

            if model.analyticsSnapshot.hasSessions {
                LatestSessionSummary()
            } else {
                BTEmptyState(
                    title: "No local takes yet",
                    message: "Record a live or sample take to make analytics, export, and review screens show real local data.",
                    systemImage: "waveform"
                )
                .accessibilityIdentifier("home.noSessions")
            }

            AccountStateCard()
        }
        .navigationTitle("Home")
        .accessibilityIdentifier("screen.home")
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            BTScreen {
                BTCard {
                    BTSectionHeader(
                        title: "Set the horn before the first take",
                        subtitle: "Choose your instrument and reference pitch. Simulator sample mode is ready; live microphone tuning runs on device and still needs physical-device validation."
                    )
                    Picker("Instrument", selection: $model.selectedInstrumentId) {
                        instrumentPickerOptions()
                    }
                    Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                }

                BTCard {
                    BTSectionHeader(
                        title: "How BrassTune records",
                        subtitle: "Live microphone mode uses iOS permission and on-device pitch detection. Simulator sample mode stays clearly labeled for repeatable testing."
                    )
                    Button {
                        model.enterGuestDemo()
                        selectedTab = .practice
                        isPresented = false
                    } label: {
                        Label("Continue as guest", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.startPractice")
                    Text("No lock means confidence is too low to save. Unstable pitch means lock exists but cents vary too much.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Setup")
        }
        .presentationDetents([.medium, .large])
    }
}

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            PracticeTunerSection(model: model, audioEngine: model.audioEngine)
            PracticeToolsCard(selectedTab: $selectedTab)
            MicrophoneSection(audioEngine: model.audioEngine)
            if !model.sessions.isEmpty {
                BTCard {
                    BTSectionHeader(title: "Saved take ready", subtitle: "Review the latest take or inspect local analytics derived from saved frames.")
                    VStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "Analytics", value: "\(model.analyticsSnapshot.sessionCount)", detail: "saved take ready", tint: BTTheme.success)
                            .accessibilityIdentifier("analytics.metrics")

                        NavigationLink {
                            SessionsView()
                        } label: {
                            Label("Review sessions", systemImage: "music.note.list")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("analytics.reviewSessions")

                        NavigationLink {
                            AnalyticsView(selectedTab: $selectedTab)
                        } label: {
                            Label("View analytics", systemImage: "chart.bar.xaxis")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("practice.viewAnalytics")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            PracticeRecordingInset(audioEngine: model.audioEngine)
        }
        .navigationTitle("Practice")
        .accessibilityIdentifier("screen.practice")
    }
}

private struct PracticeRecordingInset: View {
    @ObservedObject var audioEngine: NativeAudioEngine

    var body: some View {
        if audioEngine.recording {
            FloatingPracticeControlBar()
                .padding(.horizontal, BTSpacing.lg)
                .padding(.bottom, BTSpacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct PracticeToolsCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        BTCard {
            BTSectionHeader(title: "Practice tools", subtitle: "Metronome and score notes stay local and can run during live or sample takes.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                NavigationLink {
                    MetronomeView()
                } label: {
                    BTInsightTile(title: "Metronome", detail: "\(model.metronome.bpm) BPM, \(model.metronome.meterLabel), \(model.metronome.subdivision.title)", systemImage: "metronome", tint: BTTheme.warning, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.metronome")

                NavigationLink {
                    ScorePracticeView()
                } label: {
                    BTInsightTile(title: "Score Practice", detail: model.selectedScoreForPracticeLabel, systemImage: "doc.viewfinder", tint: BTTheme.blue, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.scorePractice")

                Button {
                    selectedTab = .coach
                } label: {
                    BTInsightTile(title: "Coach", detail: model.analyticsSnapshot.recommendation, systemImage: "sparkles", tint: BTTheme.secondaryAccent, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice.coachShortcut")
            }
        }
    }
}

private struct FloatingPracticeControlBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                primaryControls
                secondaryControls
            } else {
                primaryControls
                secondaryControls
            }
            statusRow
        }
        .padding(BTSpacing.md)
        .btGlassPanel(cornerRadius: BTTheme.radiusLarge, tint: BTTheme.surfaceWarm, interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.floatingBar")
    }

    private var primaryControls: some View {
        HStack(spacing: BTSpacing.sm) {
            Button {
                model.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Stop recording")
            .accessibilityIdentifier("practice.floating.stop")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.danger))

            Button {
                model.toggleMetronome()
            } label: {
                Label(model.metronomeRunning ? "Stop metronome" : "Start metronome", systemImage: model.metronomeRunning ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(model.metronomeRunning ? "Stop metronome" : "Start metronome")
            .accessibilityIdentifier("practice.floating.metronome")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.warning))

            VStack(spacing: 0) {
                Text("\(model.metronome.bpm)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(BTTheme.accentSoft)
                Text(model.metronome.meterLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BTTheme.muted)
            }
            .frame(minWidth: 54)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Metronome \(model.metronome.bpm) beats per minute, meter \(model.metronome.meterLabel)")
            .accessibilityIdentifier("practice.floating.bpm")

            Button {
                model.toggleMetronomeMute()
            } label: {
                Label(model.metronome.visualOnly ? "Enable speaker click" : "Use visual-only click", systemImage: model.metronome.visualOnly ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(model.metronome.visualOnly ? "Enable speaker click" : "Use visual-only metronome")
            .accessibilityHint("Visual-only mode mutes the speaker click to reduce microphone bleed.")
            .accessibilityIdentifier("practice.floating.mute")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.blue))
        }
        .frame(maxWidth: .infinity)
    }

    private var secondaryControls: some View {
        HStack(spacing: BTSpacing.sm) {
            Button {
                model.adjustTempo(by: -2)
            } label: {
                Label("Tempo down", systemImage: "minus")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Decrease tempo")
            .accessibilityIdentifier("practice.floating.tempoDown")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))

            Button {
                model.adjustTempo(by: 2)
            } label: {
                Label("Tempo up", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Increase tempo")
            .accessibilityIdentifier("practice.floating.tempoUp")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.muted))

            Button {
                model.tapTempo()
            } label: {
                Label("Tap tempo", systemImage: "hand.tap")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Tap tempo")
            .accessibilityIdentifier("practice.floating.tapTempo")
            .buttonStyle(FloatingIconButtonStyle(tint: BTTheme.secondaryAccent))
        }
        .frame(maxWidth: .infinity)
    }

    private var statusRow: some View {
        HStack(spacing: BTSpacing.sm) {
            Text(model.metronomeRunning ? "Beat \(model.metronomeTick + 1)" : "Metronome ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.metronomeRunning ? BTTheme.warning : BTTheme.muted)
                .scaleEffect(model.metronomeRunning && !reduceMotion ? 1.03 : 1)
                .accessibilityLabel(model.metronomeRunning ? "Metronome pulse" : "Metronome ready")
            Spacer()
            Text(model.activeScore?.title ?? "No score")
                .font(.caption)
                .foregroundStyle(BTTheme.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }
}

private struct FloatingIconButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.14), in: Circle())
            .overlay {
                Circle().stroke(tint.opacity(0.30), lineWidth: 1)
            }
    }
}

private struct PracticeTunerSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audioEngine: NativeAudioEngine

    var body: some View {
        let frame = audioEngine.currentFrame
        let noteLabel = frame?.writtenNoteName.map { "\($0)\(frame?.writtenOctave ?? 0)" } ?? "No lock"
        let centsLabel = frame?.centsDeviation.map { String(format: "%+.1f cents", $0) } ?? "Silence or no lock"
        let statusLabel = displayStatus(frame?.tuningStatus.rawValue ?? "ready")
        let sourceTitle = audioEngine.recording ? audioEngine.activeSource.title : model.recordingSource.title

        VStack(spacing: BTSpacing.md) {
            Button {
                if audioEngine.recording {
                    model.stopRecording()
                } else {
                    Task { await model.startRecording() }
                }
            } label: {
                Label(audioEngine.recording ? "Stop \(sourceTitle.lowercased()) take" : "Start \(sourceTitle.lowercased()) take", systemImage: audioEngine.recording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("practice.recordButton")

            BTCard(tint: BTTheme.surfaceWarm) {
                HStack {
                    BTSectionHeader(title: "Practice tuner", subtitle: "\(sourceTitle) source, local-only review")
                    Spacer()
                    BTStatusPill(text: statusLabel, tint: statusTint(frame?.tuningStatus.rawValue))
                        .accessibilityIdentifier("practice.tuningStatus")
                }
                Picker("Recording source", selection: Binding(get: { model.recordingSource }, set: { model.recordingSource = $0 })) {
                    ForEach(PracticeSessionSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(audioEngine.recording)
                .accessibilityIdentifier("practice.recordingSource")

                Text(audioEngine.recording ? "\(sourceTitle) running" : "\(sourceTitle) ready")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(audioEngine.recording ? BTTheme.secondaryAccent : BTTheme.muted)
                    .padding(.horizontal, BTSpacing.sm)
                    .padding(.vertical, BTSpacing.xs)
                    .background((audioEngine.recording ? BTTheme.secondaryAccent : BTTheme.surfaceAlt).opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("practice.recordingState")
                    .accessibilityLabel(audioEngine.recording ? "\(sourceTitle) take running" : "\(sourceTitle) take ready")
                if let notice = audioEngine.audioNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(BTTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("practice.audioNotice")
                }
                Text(noteLabel)
                    .font(.system(size: 82, weight: .bold, design: .rounded))
                    .foregroundStyle(BTTheme.accentSoft)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("practice.note")
                ZStack(alignment: .center) {
                    Capsule()
                        .fill(BTTheme.surfaceAlt)
                        .frame(height: 14)
                    Rectangle()
                        .fill(LinearGradient(colors: [BTTheme.danger, BTTheme.warning, BTTheme.success, BTTheme.warning, BTTheme.danger], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .clipShape(Capsule())
                    Rectangle()
                        .fill(BTTheme.accentSoft)
                        .frame(width: 4, height: 34)
                        .offset(x: needleOffset(frame?.centsDeviation))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("practice.tunerNeedle")
                Text(centsLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BTTheme.muted)
                    .accessibilityIdentifier("practice.cents")
            }
        }
    }
}

private func needleOffset(_ cents: Double?) -> CGFloat {
    let clamped = min(max(cents ?? 0, -25), 25)
    return CGFloat(clamped / 25) * 120
}

private struct MicrophoneSection: View {
    @ObservedObject var audioEngine: NativeAudioEngine

    var body: some View {
        BTCard {
            BTSectionHeader(
                title: "Microphone",
                subtitle: "Live acoustic capture uses AVAudioEngine on device. Use headphones or visual-only metronome while validating click bleed."
            )
            Button {
                Task { _ = await audioEngine.requestMicrophonePermission() }
            } label: {
                Label("Request microphone permission", systemImage: "mic")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.microphonePermission")
            if audioEngine.permissionDenied {
                Text("Microphone denied. You can still use sample mode, metronome, and score practice, or reopen iOS Settings to allow access.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.danger)
                    .accessibilityIdentifier("practice.microphoneDenied")
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                } label: {
                    Label("Open iOS Settings", systemImage: "gearshape")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("practice.openIOSSettings")
            }
        }
    }
}

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTSectionHeader(
                title: "Saved sessions",
                subtitle: "Local live and sample takes are available for review, export, and deletion."
            )
            if model.sessions.isEmpty {
                BTEmptyState(title: "No saved sessions", message: "Stop a live or sample take from Practice to create a local review session.", systemImage: "tray")
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
        .navigationTitle("Sessions")
        .accessibilityIdentifier("screen.sessions")
    }
}

private struct SessionRow: View {
    let session: PracticeSession

    var body: some View {
        BTCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BTSpacing.sm) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("sessions.sessionName")
                    Text("\(instrumentName(session.instrumentId)) - \(session.source.title) - \(session.validFrameCount) valid frames")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: BTSpacing.md) {
                BTMetricTile(title: "Avg abs", value: String(format: "%.1f", session.averageAbsCents), detail: "cents")
                BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", session.inTunePercentage))%", detail: "within 5 cents", tint: BTTheme.success)
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
                BTCard {
                    BTSectionHeader(title: session.name, subtitle: "Review and export")
                    BTStatusPill(text: session.source.title, tint: session.source == .live ? BTTheme.success : BTTheme.warning)
                        .accessibilityIdentifier("session.source")
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "Avg abs", value: String(format: "%.1f", session.averageAbsCents), detail: "cents")
                        BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", session.inTunePercentage))%", detail: "within 5 cents", tint: BTTheme.success)
                    }
                    Text("Pitch coverage: \(session.pitchCoverageLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("session.pitchCoverage")
                }

                BTCard {
                    BTSectionHeader(title: "Relisten", subtitle: session.retainedRecordingURL == nil ? "No playback was saved for this take." : "Playback is ready.")
                }

                BTCard {
                    BTSectionHeader(title: "Export", subtitle: "Share a text summary with metrics and a cents preview.")
                    ShareLink(item: session.exportText) {
                        Label("Share session summary", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("session.exportButton")
                }

                BTCard {
                    BTSectionHeader(title: "Delete", subtitle: "Removes this local session from the native app.")
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete session", systemImage: "trash")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("session.deleteButton")
                }
            } else {
                BTEmptyState(title: "Session deleted", message: "This local session is no longer available.", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("session.deletedState")
            }
        }
        .navigationTitle("Session review")
        .accessibilityIdentifier("screen.sessionDetail")
        .confirmationDialog("Delete this local session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete local session", role: .destructive) {
                if let session {
                    model.deleteSession(id: session.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved take and its local metrics from this device.")
        }
    }
}

struct AnalyticsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        let snapshot = model.analyticsSnapshot
        BTScreen {
            BTSectionHeader(
                title: "Local analytics",
                subtitle: "Derived from live and sample takes saved on this device."
            )
            if snapshot.hasSessions {
                BTCard {
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "Sessions", value: "\(snapshot.sessionCount)", detail: "\(snapshot.validFrameCount) valid frames")
                            .accessibilityIdentifier("analytics.metrics")
                        BTMetricTile(title: "Avg abs", value: String(format: "%.1f", snapshot.averageAbsCents), detail: "cents", tint: BTTheme.secondaryAccent)
                    }
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", snapshot.averageInTunePercentage))%", detail: "all local frames", tint: BTTheme.success)
                        BTMetricTile(title: "Practice", value: "\(String(format: "%.0f", snapshot.totalPracticeSeconds))s", detail: "saved duration")
                    }
                }

                BTCard {
                    BTSectionHeader(title: "Recommendation", subtitle: snapshot.recommendation)
                    if let best = snapshot.bestSessionName {
                        Label("Best local take: \(best)", systemImage: "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(BTTheme.success)
                            .accessibilityIdentifier("analytics.bestSession")
                    }
                    if let latest = snapshot.latestSessionName {
                        Label("Latest take: \(latest), \(String(format: "%.0f", snapshot.latestSessionInTunePercentage))% in tune", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("analytics.latestSession")
                    }
                    NavigationLink {
                        SessionsView()
                    } label: {
                        Label("Review sessions", systemImage: "music.note.list")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("analytics.reviewSessions")
                }
            } else {
                BTEmptyState(
                    title: "Analytics need local sessions",
                    message: "Record a live or sample take to calculate in-tune percentage, average cents, and practice recommendations on device.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .accessibilityIdentifier("analytics.empty")
                Button {
                    selectedTab = .practice
                } label: {
                    Label("Record a take", systemImage: "record.circle")
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("analytics.recordSample")
            }
        }
        .navigationTitle("Analytics")
        .accessibilityIdentifier("screen.analytics")
    }
}

struct CoachNativeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Coach",
                title: "Practice plan",
                subtitle: "Local native guidance uses saved live/sample evidence and stays conservative until account-backed coaching is validated.",
                trailing: model.authState.usesRemoteAccount ? "Account" : "Local"
            )
            if model.analyticsSnapshot.hasUsableEvidence {
                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(title: "Next best drill", subtitle: model.analyticsSnapshot.recommendation)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                        BTInsightTile(title: "Long tones", detail: "Hold the focus note for 8 counts at mezzo piano.", systemImage: "wind", tint: BTTheme.secondaryAccent)
                        BTInsightTile(title: "Drone match", detail: "Match the center before moving to slurs.", systemImage: "waveform.path", tint: BTTheme.accent)
                        BTInsightTile(title: "Release audit", detail: "Check that the final second stays within 5 cents.", systemImage: "checkmark.seal", tint: BTTheme.success)
                    }
                }
            } else if model.analyticsSnapshot.hasSessions {
                BTEmptyState(title: "More locked notes needed", message: model.analyticsSnapshot.recommendation, systemImage: "sparkles")
                Button {
                    selectedTab = .practice
                } label: {
                    Label("Record another take", systemImage: "record.circle")
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("coach.recordMore")
            } else {
                BTEmptyState(title: "Coach needs a take", message: "Record a live or sample take first so native coaching can use local intonation evidence.", systemImage: "sparkles")
                Button {
                    selectedTab = .practice
                } label: {
                    Label("Record a take", systemImage: "record.circle")
                }
                .buttonStyle(BTPrimaryButtonStyle())
            }
        }
        .navigationTitle("Coach")
        .accessibilityIdentifier("screen.coach")
    }
}

struct MoreHubView: View {
    @Binding var onboardingPresented: Bool
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Workspace",
                title: "More",
                subtitle: "Saved work, practice tools, ensemble, account settings, and release-critical policy surfaces.",
                trailing: "Bento"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                MoreHubLink(title: "Sessions", detail: "Review saved takes and exports.", systemImage: "music.note.list", tint: BTTheme.accent) {
                    SessionsView()
                }
                MoreHubLink(title: "Metronome", detail: "Tempo, tap, meter, mute, visual pulse.", systemImage: "metronome", tint: BTTheme.warning) {
                    MetronomeView()
                }
                MoreHubLink(title: "Score Practice", detail: "Files, Photos, pages, notes.", systemImage: "doc.viewfinder", tint: BTTheme.blue) {
                    ScorePracticeView()
                }
                MoreHubLink(title: "Progress", detail: "Local trend and heatmap.", systemImage: "chart.line.uptrend.xyaxis", tint: BTTheme.success) {
                    ProgressNativeView()
                }
                MoreHubLink(title: "Ensemble", detail: "Demo roster until account services are configured.", systemImage: "person.3", tint: BTTheme.secondaryAccent) {
                    EnsembleView(selectedTab: $selectedTab)
                }
                MoreHubLink(title: "Settings", detail: "Account, tuner, data, legal.", systemImage: "gearshape", tint: BTTheme.muted) {
                    SettingsView(onboardingPresented: $onboardingPresented)
                }
                MoreHubLink(title: "Audio Lab", detail: "Permission and detector state.", systemImage: "waveform", tint: BTTheme.blue) {
                    AudioLabView()
                }
                MoreHubLink(title: "Privacy", detail: "Data use and account lifecycle.", systemImage: "hand.raised", tint: BTTheme.accent) {
                    LegalDetailView(kind: .privacy)
                }
                MoreHubLink(title: "Terms", detail: "Use rules and limitations.", systemImage: "doc.text", tint: BTTheme.accent) {
                    LegalDetailView(kind: .terms)
                }
                MoreHubLink(title: "Support", detail: "Issue reporting guidance.", systemImage: "questionmark.circle", tint: BTTheme.secondaryAccent) {
                    LegalDetailView(kind: .support)
                }
            }
        }
        .navigationTitle("More")
        .accessibilityIdentifier("screen.more")
    }
}

private struct MoreHubLink<Destination: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let destination: Destination

    init(title: String, detail: String, systemImage: String, tint: Color, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            BTInsightTile(title: title, detail: detail, systemImage: systemImage, tint: tint, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
    }
}

struct MetronomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Practice tool",
                title: "Metronome",
                subtitle: "Visual-first native metronome controls that can stay running while a live or sample take records.",
                trailing: model.metronomeRunning ? "Running" : "Ready"
            )

            BTCard(tint: BTTheme.surfaceWarm) {
                HStack(alignment: .center, spacing: BTSpacing.lg) {
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        Text("\(model.metronome.bpm)")
                            .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
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
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("metronome.toggle")
            }

            BTCard {
                BTSectionHeader(title: "Tempo", subtitle: "Tap or step tempo. The floating recording controls use the same settings.")
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
                BTSectionHeader(title: "Meter and feel", subtitle: "Speaker click is muted by default to reduce microphone bleed during live capture.")
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
                .accessibilityHint("Visual-only mode mutes the speaker click to reduce microphone bleed.")

                Toggle("Haptic pulse", isOn: Binding(get: { model.metronome.hapticsEnabled }, set: { model.metronome.hapticsEnabled = $0 }))
                    .accessibilityIdentifier("metronome.haptics")

                Slider(value: Binding(get: { model.metronome.volume }, set: { model.setMetronomeVolume($0) }), in: 0...1)
                    .disabled(model.metronome.visualOnly)
                    .accessibilityLabel("Metronome volume")
                    .accessibilityIdentifier("metronome.volume")

                Text("For live microphone recording, validate headphones, visual-only mode, route changes, and click bleed on a physical device.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                eyebrow: "Score assist",
                title: "Score Practice",
                subtitle: "Import local PDF or image scores, mark problem passages, and keep metadata on device.",
                trailing: "\(model.scores.count)"
            )

            BTCard {
                BTSectionHeader(title: "Import", subtitle: "Files and Photos stay local by default. Camera capture is hidden until it has a real native flow and device validation.")
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

                    Button {
                        model.importSampleScore()
                    } label: {
                        Label("Sample", systemImage: "music.note")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("score.import.sample")
                }

                Text("Score intelligence here means local page previews, cleanup controls, OCR-style text suggestions when PDF text is available, and manual annotations. BrassTune does not upload copyrighted scores or claim optical music recognition.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let importError {
                    Text(importError)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BTTheme.danger)
                        .accessibilityIdentifier("score.import.error")
                }
            }

            if model.scores.isEmpty {
                BTEmptyState(title: "No score imported", message: "Import a local PDF/image or add the synthetic sample score to rehearse the workflow.", systemImage: "doc.viewfinder")
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
    let score: ImportedScore

    var body: some View {
        BTCard(tint: score.id == model.activeScoreID ? BTTheme.surfaceWarm : BTTheme.surface) {
            HStack(alignment: .top, spacing: BTSpacing.md) {
                ScoreThumbnailView(page: score.selectedPage)
                    .frame(width: 98, height: 132)
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

            if !page.textSuggestions.isEmpty {
                Text("Text suggestions: \(page.textSuggestions.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("score.textSuggestions")
            }

            if !page.suggestedRegions.isEmpty {
                Text("Suggested regions: \(page.suggestedRegions.map(\.label).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("score.regions")
            }
        }
        .padding(BTSpacing.md)
        .btGlassPanel(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt)
    }
}

private struct ScoreAnnotationEditor: View {
    @EnvironmentObject private var model: AppModel
    let score: ImportedScore

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            BTSectionHeader(title: "Practice annotation", subtitle: "Manual notes are the reliable fallback when OMR is not available.")
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
        .btGlassPanel(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt)
    }
}

struct ProgressNativeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let snapshot = model.analyticsSnapshot
        BTScreen {
            BTPageHeader(
                eyebrow: "Local progress",
                title: "Progress",
                subtitle: snapshot.hasUsableEvidence ? "Local trend summaries from valid live/sample frames." : "Progress appears after a saved take has valid pitch evidence.",
                trailing: "\(snapshot.sessionCount)"
            )

            if snapshot.hasUsableEvidence {
                BTCard {
                    BTSectionHeader(title: "Trend", subtitle: snapshot.recommendation)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                        BTMetricTile(title: "Sessions", value: "\(snapshot.sessionCount)", detail: "local")
                        BTMetricTile(title: "Valid frames", value: "\(snapshot.validFrameCount)", detail: "saved")
                        BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", snapshot.averageInTunePercentage))%", detail: "within 5 cents", tint: BTTheme.success)
                    }
                }
                BTCard {
                    BTSectionHeader(title: "Practice heatmap", subtitle: "Each block represents one saved local session.")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: BTSpacing.xs), count: min(7, max(1, model.sessions.count))), spacing: BTSpacing.xs) {
                        ForEach(model.sessions.prefix(28)) { session in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.inTunePercentage >= 70 ? BTTheme.success : (session.averageAbsCents > 8 ? BTTheme.warning : BTTheme.blue))
                                .frame(height: 34)
                                .accessibilityLabel("\(session.name), \(String(format: "%.0f", session.inTunePercentage)) percent in tune")
                        }
                    }
                    .accessibilityIdentifier("progress.heatmap")
                }
            } else {
                BTEmptyState(title: "More data needed", message: "Record a guided live or sample take with locked notes before BrassTune summarizes progress.", systemImage: "chart.line.uptrend.xyaxis")
                    .accessibilityIdentifier("progress.empty")
            }
        }
        .navigationTitle("Progress")
        .accessibilityIdentifier("screen.progress")
    }
}

struct AudioLabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Diagnostics",
                title: "Audio Lab",
                subtitle: "Native beta diagnostics are local. Live microphone behavior still needs physical-device validation.",
                trailing: model.audioEngine.permissionDenied ? "Denied" : "Ready"
            )

            BTCard {
                BTSectionHeader(title: "Current detector state", subtitle: "Live mode uses AVAudioEngine; sample mode uses deterministic frames for simulator coverage.")
                let frame = model.audioEngine.currentFrame
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                    BTMetricTile(title: "Frequency", value: frame?.frequencyHz.map { String(format: "%.1f", $0) } ?? "--", detail: "Hz")
                    BTMetricTile(title: "Confidence", value: frame.map { String(format: "%.2f", $0.confidence) } ?? "--", detail: model.audioEngine.activeSource.title)
                    BTMetricTile(title: "RMS", value: frame.map { String(format: "%.2f", $0.rms) } ?? "--", detail: "level")
                    BTMetricTile(title: "Frames", value: "\(model.audioEngine.frames.count)", detail: "buffered")
                }
                Button {
                    Task { _ = await model.audioEngine.requestMicrophonePermission() }
                } label: {
                    Label("Check microphone permission", systemImage: "mic")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("audioLab.permission")
            }
        }
        .navigationTitle("Audio Lab")
        .accessibilityIdentifier("screen.audioLab")
    }
}

private struct NativeToolShell: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        BTScreen {
            BTPageHeader(eyebrow: "Native parity", title: title, subtitle: subtitle, trailing: "Planned")
            BTCard {
                BTInsightTile(title: "Current state", detail: "This native surface is intentionally conservative until it matches the web workflow and has simulator plus physical-device evidence.", systemImage: systemImage, tint: BTTheme.warning)
                BTInsightTile(title: "Guest practice remains available", detail: "Core native tuner, saved sessions, analytics, account settings, and legal surfaces are still usable.", systemImage: "checkmark.circle", tint: BTTheme.success)
            }
        }
        .navigationTitle(title)
        .accessibilityIdentifier("screen.tool.\(title)")
    }
}

struct EnsembleView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTSectionHeader(
                title: "Ensemble",
                subtitle: "Memberships and teacher assignments require an account-backed workspace."
            )
            switch model.authState {
            case .guest:
                BTCard {
                    HStack {
                        BTSectionHeader(title: "Demo preview", subtitle: "This is sample ensemble data, not a live roster.")
                        Spacer()
                        BTStatusPill(text: "Demo only", tint: BTTheme.warning)
                            .accessibilityIdentifier("ensemble.demoBadge")
                    }
                    ForEach(model.ensembles) { ensemble in
                        EnsembleSummaryCard(ensemble: ensemble)
                    }
                    Button {
                        selectedTab = .more
                    } label: {
                        Label("Sign in to load real ensemble data", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("ensemble.signInPrompt")
                }
            case .signedOut:
                AccountRequiredCard(
                    title: "Account required",
                    message: model.accountUnavailableMessage ?? "Sign in to load ensemble memberships from your teacher or organization.",
                    actionTitle: "Open Settings",
                    action: { selectedTab = .more }
                )
                .accessibilityIdentifier("ensemble.accountRequired")
            case .emailConfirmationRequired(let email):
                AccountRequiredCard(
                    title: "Confirm email",
                    message: "Confirm \(email) before BrassTune can load account-backed ensemble memberships.",
                    actionTitle: "Open Settings",
                    action: { selectedTab = .more }
                )
                .accessibilityIdentifier("ensemble.confirmEmail")
            case .signedIn:
                if model.ensembles.isEmpty {
                    BTEmptyState(
                        title: "No ensemble memberships",
                        message: "This account is signed in, but no native ensemble memberships are available yet.",
                        systemImage: "person.3"
                    )
                    .accessibilityIdentifier("ensemble.empty")
                } else {
                    ForEach(model.ensembles) { ensemble in
                        EnsembleSummaryCard(ensemble: ensemble)
                    }
                }
            }
        }
        .navigationTitle("Ensemble")
        .accessibilityIdentifier("screen.ensemble")
    }
}

private struct EnsembleSummaryCard: View {
    let ensemble: EnsembleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            Text(ensemble.name)
                .font(.headline)
            HStack(spacing: BTSpacing.md) {
                BTMetricTile(title: "Role", value: ensemble.role, detail: nil)
                BTMetricTile(title: "Members", value: "\(ensemble.activeMembers)", detail: "active", tint: BTTheme.secondaryAccent)
            }
            Text(ensemble.focus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ensemble.summaryCard")
    }
}

private struct LatestSessionSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.sessions.first {
            BTCard {
                BTSectionHeader(title: "Latest take", subtitle: session.name)
                HStack(spacing: BTSpacing.md) {
                    BTMetricTile(title: "Avg abs", value: String(format: "%.1f", session.averageAbsCents), detail: "cents")
                    BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", session.inTunePercentage))%", detail: "within 5 cents", tint: BTTheme.success)
                }
            }
            .accessibilityIdentifier("home.latestSession")
        }
    }
}

private struct AccountStateCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTCard {
            HStack {
                BTSectionHeader(title: "Account", subtitle: accountMessage)
                Spacer()
                BTStatusPill(text: model.accountFeaturesEnabled ? "Configured" : "Disabled", tint: model.accountFeaturesEnabled ? BTTheme.success : BTTheme.warning)
                    .accessibilityIdentifier("account.configStatus")
            }
        }
        .accessibilityIdentifier("account.stateCard")
    }

    private var accountMessage: String {
        switch model.authState {
        case .guest:
            return model.accountUnavailableMessage ?? "Guest practice is active. Sign in to use account services."
        case .signedOut:
            return model.accountUnavailableMessage ?? "Signed out. Local practice data stays on this device."
        case .signedIn(let email):
            return "Signed in as \(email)."
        case .emailConfirmationRequired(let email):
            return "Confirm \(email) to complete account setup."
        }
    }
}

private struct AccountRequiredCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        BTCard {
            BTSectionHeader(title: title, subtitle: message)
            Button(action: action) {
                Label(actionTitle, systemImage: "gearshape")
            }
            .buttonStyle(BTSecondaryButtonStyle())
        }
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

private func instrumentName(_ id: String) -> String {
    switch id {
    case "trumpet": return "Trumpet"
    case "horn": return "Horn"
    case "trombone": return "Trombone"
    case "euphonium": return "Euphonium"
    case "tuba": return "Tuba"
    default: return id.capitalized
    }
}

private func displayStatus(_ rawValue: String) -> String {
    rawValue.replacingOccurrences(of: "_", with: " ").capitalized
}

private func statusTint(_ rawValue: String?) -> Color {
    switch rawValue {
    case "in_tune": return BTTheme.success
    case "sharp": return BTTheme.sharp
    case "flat": return BTTheme.flat
    case "no_lock", "unstable": return BTTheme.warning
    case "silence": return BTTheme.unstable
    default: return BTTheme.accent
    }
}
