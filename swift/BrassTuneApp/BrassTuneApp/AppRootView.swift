import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case practice
    case sessions
    case analytics
    case ensemble
    case settings

    var id: String { rawValue }
}

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .home
    @State private var onboardingPresented: Bool
    private let settingsOnlyLaunch: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        settingsOnlyLaunch = arguments.contains("UITEST_SETTINGS")
        let uiTestMode = arguments.contains("UITEST_DEMO") || arguments.contains("UITEST_SETTINGS")
        _onboardingPresented = State(initialValue: !uiTestMode)
    }

    var body: some View {
        Group {
            if settingsOnlyLaunch {
                NavigationStack { SettingsView(onboardingPresented: $onboardingPresented) }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack { HomeView(selectedTab: $selectedTab) }
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(AppTab.home)
                    NavigationStack { PracticeView() }
                        .tabItem { Label("Practice", systemImage: "gauge.with.dots.needle.67percent") }
                        .tag(AppTab.practice)
                    NavigationStack { SessionsView() }
                        .tabItem { Label("Sessions", systemImage: "music.note.list") }
                        .tag(AppTab.sessions)
                    NavigationStack { AnalyticsView() }
                        .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
                        .tag(AppTab.analytics)
                    NavigationStack { EnsembleView() }
                        .tabItem { Label("Ensemble", systemImage: "person.3") }
                        .tag(AppTab.ensemble)
                    NavigationStack { SettingsView(onboardingPresented: $onboardingPresented) }
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
                .sheet(isPresented: $onboardingPresented) {
                    OnboardingView(isPresented: $onboardingPresented)
                }
            }
        }
        .task {
            await model.restoreSession()
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: AppTab

    var body: some View {
        List {
            Section("Today") {
                Text("Center D5 before expanding range.")
                    .font(.headline)
                Text("Reference pitch A4 \(model.referencePitchHz, specifier: "%.1f") Hz")
                Button("Start practice") {
                    selectedTab = .practice
                }
                .accessibilityIdentifier("home.startPractice")
            }
            Section("Account") {
                switch model.authState {
                case .guest: Text("Guest demo")
                case .signedOut: Text("Signed out")
                case .signedIn(let email): Text("Signed in as \(email)")
                case .emailConfirmationRequired(let email): Text("Confirm \(email)")
                }
            }
        }
        .navigationTitle("BrassTune")
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("Instrument", selection: $model.selectedInstrumentId) {
                    Text("Trumpet in Bb").tag("trumpet")
                    Text("Horn in F").tag("horn")
                    Text("Trombone").tag("trombone")
                    Text("Euphonium").tag("euphonium")
                    Text("Tuba").tag("tuba")
                }
                Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                Section("Input") {
                    Text("Try a guided sample take, or enable the microphone for live tuning. Microphone mode requires permission.")
                    Text("No lock means confidence is too low to save. Unstable pitch means lock exists but cents vary too much.")
                }
            }
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start practice") {
                        model.enterGuestDemo()
                        isPresented = false
                    }
                    .accessibilityIdentifier("onboarding.startPractice")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Practice tuner") {
                let frame = model.audioEngine.currentFrame
                let noteLabel = frame?.writtenNoteName.map { "\($0)\(frame?.writtenOctave ?? 0)" } ?? "No lock"
                let centsLabel = frame?.centsDeviation.map { String(format: "%+.1f cents", $0) } ?? "Silence or no lock"
                Text(noteLabel)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("practice.note")
                Text(centsLabel)
                Text(frame?.tuningStatus.rawValue.replacingOccurrences(of: "_", with: " ") ?? "ready")
                Button(model.audioEngine.recording ? "Stop sample take" : "Start sample take") {
                    if model.audioEngine.recording {
                        model.stopDemoRecording()
                    } else {
                        model.startDemoRecording()
                    }
                }
                .accessibilityIdentifier("practice.recordButton")
            }
            Section("Microphone") {
                Button("Request microphone permission") {
                    Task { _ = await model.audioEngine.requestMicrophonePermission() }
                }
                if model.audioEngine.permissionDenied {
                    Text("Microphone denied. Open Settings to allow access.")
                }
            }
        }
        .navigationTitle("Practice")
    }
}

struct SessionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.sessions.isEmpty {
                Text("No saved sessions")
            }
            ForEach(model.sessions) { session in
                NavigationLink(session.name) {
                    SessionDetailView(session: session)
                }
            }
        }
        .navigationTitle("Sessions")
    }
}

struct SessionDetailView: View {
    let session: PracticeSession

    var body: some View {
        List {
            Section("Review") {
                Text("\(session.averageAbsCents, specifier: "%.1f") cents avg abs")
                Text("\(session.inTunePercentage, specifier: "%.0f")% in tune")
            }
            Section("Relisten") {
                Text(session.retainedRecordingURL == nil ? "No playback saved for this take" : "Playback ready")
            }
            Section("Export") {
                ShareLink(item: session.name)
            }
            Section("Delete") {
                Button("Delete session", role: .destructive) {}
            }
        }
        .navigationTitle("Session review")
    }
}

struct AnalyticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Progress") {
                Text("\(model.sessions.count) sessions")
                Text("Heat map will appear after more saved takes.")
            }
            Section("Recommendations") {
                Text("Practice plan: long tones, drone match, then repertoire excerpt.")
            }
        }
        .navigationTitle("Analytics")
    }
}

struct EnsembleView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(model.ensembles) { ensemble in
                Section(ensemble.name) {
                    Text("Role: \(ensemble.role)")
                    Text("Active members: \(ensemble.activeMembers)")
                    Text(ensemble.focus)
                }
            }
            if model.ensembles.isEmpty {
                Text("No ensemble memberships")
            }
        }
        .navigationTitle("Ensemble")
    }
}
