import SwiftUI

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
                    NavigationStack { HomeView(selectedTab: $selectedTab) }
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
                    OnboardingView(isPresented: $onboardingPresented)
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
                    message: "Record a sample take to make analytics, export, and review screens show real local data.",
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

    var body: some View {
        NavigationStack {
            BTScreen {
                BTCard {
                    BTSectionHeader(
                        title: "Set the horn before the first take",
                        subtitle: "Choose your instrument and reference pitch. Live microphone mode still requires iOS permission."
                    )
                    Picker("Instrument", selection: $model.selectedInstrumentId) {
                        instrumentPickerOptions()
                    }
                    Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                }

                BTCard {
                    BTSectionHeader(
                        title: "How BrassTune records",
                        subtitle: "No lock means confidence is too low to save. Unstable pitch means lock exists but cents vary too much."
                    )
                    Button {
                        model.enterGuestDemo()
                        isPresented = false
                    } label: {
                        Label("Start practice", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.startPractice")
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                BTInsightTile(title: "Metronome", detail: "Tempo and count-in controls live in More.", systemImage: "metronome", tint: BTTheme.warning)
                BTInsightTile(title: "Score practice", detail: "Score import remains a local/demo shell in native until physical-device validation.", systemImage: "doc.viewfinder", tint: BTTheme.blue)
            }
        }
        .navigationTitle("Practice")
        .accessibilityIdentifier("screen.practice")
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

        VStack(spacing: BTSpacing.md) {
            Button {
                if audioEngine.recording {
                    model.stopDemoRecording()
                } else {
                    model.startDemoRecording()
                }
            } label: {
                Label(audioEngine.recording ? "Stop sample take" : "Start sample take", systemImage: audioEngine.recording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("practice.recordButton")

            BTCard(tint: BTTheme.surfaceWarm) {
                HStack {
                    BTSectionHeader(title: "Practice tuner", subtitle: "Local sample take")
                    Spacer()
                    BTStatusPill(text: statusLabel, tint: statusTint(frame?.tuningStatus.rawValue))
                        .accessibilityIdentifier("practice.tuningStatus")
                }
                Text(audioEngine.recording ? "Recording" : "Ready")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(audioEngine.recording ? BTTheme.secondaryAccent : BTTheme.muted)
                    .padding(.horizontal, BTSpacing.sm)
                    .padding(.vertical, BTSpacing.xs)
                    .background((audioEngine.recording ? BTTheme.secondaryAccent : BTTheme.surfaceAlt).opacity(0.14), in: Capsule())
                    .accessibilityIdentifier("practice.recordingState")
                    .accessibilityLabel(audioEngine.recording ? "Recording" : "Ready")
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
                subtitle: "This repository build uses permission checks plus deterministic sample takes; physical microphone tuning still requires the native audio path."
            )
            Button {
                Task { _ = await audioEngine.requestMicrophonePermission() }
            } label: {
                Label("Request microphone permission", systemImage: "mic")
            }
            .buttonStyle(BTSecondaryButtonStyle())
            .accessibilityIdentifier("practice.microphonePermission")
            if audioEngine.permissionDenied {
                Text("Microphone denied. Open Settings to allow access.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.danger)
                    .accessibilityIdentifier("practice.microphoneDenied")
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
                subtitle: "Local sample takes are available for review, export, and deletion."
            )
            if model.sessions.isEmpty {
                BTEmptyState(title: "No saved sessions", message: "Stop a sample take from Practice to create a local review session.", systemImage: "tray")
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
                    Text("\(instrumentName(session.instrumentId)) - \(session.validFrameCount) valid frames")
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
    let sessionID: PracticeSession.ID

    private var session: PracticeSession? {
        model.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        BTScreen {
            if let session {
                BTCard {
                    BTSectionHeader(title: session.name, subtitle: "Review and export")
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
                        model.deleteSession(id: session.id)
                        dismiss()
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
                subtitle: "Derived from sample takes saved on this device."
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
                        BTMetricTile(title: "Practice", value: "\(String(format: "%.0f", snapshot.totalPracticeSeconds))s", detail: "sample duration")
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
                    message: "Record a sample take to calculate in-tune percentage, average cents, and practice recommendations on device.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .accessibilityIdentifier("analytics.empty")
                Button {
                    selectedTab = .practice
                } label: {
                    Label("Record sample take", systemImage: "record.circle")
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
                subtitle: "Native guidance mirrors the web cockpit with local, honest recommendations until live account coaching is validated.",
                trailing: model.authState.usesRemoteAccount ? "Account" : "Local"
            )
            if model.analyticsSnapshot.hasSessions {
                BTCard(tint: BTTheme.surfaceWarm) {
                    BTSectionHeader(title: "Next best drill", subtitle: model.analyticsSnapshot.recommendation)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: BTSpacing.md)], spacing: BTSpacing.md) {
                        BTInsightTile(title: "Long tones", detail: "Hold the focus note for 8 counts at mezzo piano.", systemImage: "wind", tint: BTTheme.secondaryAccent)
                        BTInsightTile(title: "Drone match", detail: "Match the center before moving to slurs.", systemImage: "waveform.path", tint: BTTheme.accent)
                        BTInsightTile(title: "Release audit", detail: "Check that the final second stays within 5 cents.", systemImage: "checkmark.seal", tint: BTTheme.success)
                    }
                }
            } else {
                BTEmptyState(title: "Coach needs a take", message: "Record a sample take first so native coaching can use local intonation evidence.", systemImage: "sparkles")
                Button {
                    selectedTab = .practice
                } label: {
                    Label("Record sample take", systemImage: "record.circle")
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
                MoreHubLink(title: "Metronome", detail: "Tempo, meter, and count-in shell.", systemImage: "metronome", tint: BTTheme.warning) {
                    NativeToolShell(title: "Metronome", subtitle: "Foreground pulse controls are planned for native parity. Use the web app for full ramp/subdivision controls until this shell is implemented.", systemImage: "metronome")
                }
                MoreHubLink(title: "Score Practice", detail: "Score workflow placeholder.", systemImage: "doc.viewfinder", tint: BTTheme.blue) {
                    NativeToolShell(title: "Score Practice", subtitle: "Native score import remains an honest shell until PDF/image import and physical-device validation are complete.", systemImage: "doc.viewfinder")
                }
                MoreHubLink(title: "Progress", detail: "Long-term trend surface.", systemImage: "chart.line.uptrend.xyaxis", tint: BTTheme.success) {
                    NativeToolShell(title: "Progress", subtitle: "Progress trends currently use web/backend data. Native local trend charts will build on saved sample takes.", systemImage: "chart.line.uptrend.xyaxis")
                }
                MoreHubLink(title: "Ensemble", detail: "Director and membership state.", systemImage: "person.3", tint: BTTheme.secondaryAccent) {
                    EnsembleView(selectedTab: $selectedTab)
                }
                MoreHubLink(title: "Settings", detail: "Account, tuner, data, legal.", systemImage: "gearshape", tint: BTTheme.muted) {
                    SettingsView(onboardingPresented: $onboardingPresented)
                }
                MoreHubLink(title: "Audio Lab", detail: "Diagnostics placeholder.", systemImage: "waveform", tint: BTTheme.blue) {
                    NativeToolShell(title: "Audio Lab", subtitle: "Native audio diagnostics are limited to permission and sample-take evidence in this build. Physical microphone quality still needs device validation.", systemImage: "waveform")
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
            BTInsightTile(title: title, detail: detail, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
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
            return model.accountUnavailableMessage ?? "Guest practice is active. Sign in to sync account-backed data."
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
    case "sharp", "flat": return BTTheme.secondaryAccent
    case "unstable": return BTTheme.warning
    case "silence": return .secondary
    default: return BTTheme.accent
    }
}
