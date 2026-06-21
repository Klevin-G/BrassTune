import AuthenticationServices
import PhotosUI
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case practice
    case score
    case sessions
    case more

    var id: String { rawValue }

    var feature: NativeFeature {
        switch self {
        case .home: return .home
        case .practice: return .practice
        case .score: return .score
        case .sessions: return .sessions
        case .more: return .metronome
        }
    }

    var title: String {
        self == .more ? "More" : feature.title
    }

    var systemImage: String {
        self == .more ? "ellipsis.circle" : feature.systemImage
    }
}

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.btPalette) private var palette
    @State private var selectedTab: AppTab = .home
    @State private var selectedFeature: NativeFeature = .home
    @State private var onboardingPresented: Bool
    private let resetUITestState: Bool
    private let settingsOnlyLaunch: Bool
    private let uiTestMode: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        settingsOnlyLaunch = arguments.contains("UITEST_SETTINGS")
        resetUITestState = arguments.contains("UITEST_RESET_STATE")
        uiTestMode = arguments.contains("UITEST_DEMO") || arguments.contains("UITEST_SETTINGS")
        _onboardingPresented = State(initialValue: false)
    }

    var body: some View {
        Group {
            if settingsOnlyLaunch {
                NavigationStack { SettingsView(onboardingPresented: $onboardingPresented) }
            } else {
                switch model.launchState {
                case .restoring:
                    RestoringSessionView()
                case .gateway:
                    AuthGatewayView()
                case .app:
                    if horizontalSizeClass == .regular {
                        iPadShell
                    } else {
                        iPhoneShell
                    }
                }
            }
        }
        .sheet(isPresented: $onboardingPresented) {
            OnboardingView(isPresented: $onboardingPresented)
        }
        .task {
            if resetUITestState {
                model.resetForUITesting()
            }
            if uiTestMode {
                model.continueAsGuest()
                return
            }
            await model.restoreSession()
        }
    }

    private var iPhoneShell: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab) }
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)
            NavigationStack { PracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, deterministicAudio: uiTestMode) }
                .tabItem { Label(AppTab.practice.title, systemImage: AppTab.practice.systemImage) }
                .tag(AppTab.practice)
            NavigationStack { ScorePracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab) }
                .tabItem { Label(AppTab.score.title, systemImage: AppTab.score.systemImage) }
                .tag(AppTab.score)
            NavigationStack { SessionsView() }
                .tabItem { Label(AppTab.sessions.title, systemImage: AppTab.sessions.systemImage) }
                .tag(AppTab.sessions)
            NavigationStack { compactMoreContent }
                .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.systemImage) }
                .tag(AppTab.more)
        }
        .accessibilityIdentifier("shell.iphoneTabs")
        .toolbarBackground(palette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    @ViewBuilder
    private var compactMoreContent: some View {
        switch selectedFeature {
        case .metronome, .analytics, .progress, .coach, .ensemble, .settings, .account, .privacy, .terms, .support:
            featureView(selectedFeature)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("More") {
                            selectedFeature = .home
                        }
                    }
                }
        default:
            MoreView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, onboardingPresented: $onboardingPresented)
        }
    }

    private var iPadShell: some View {
        NavigationSplitView {
            List {
                ForEach(NativeFeature.allCases) { feature in
                    Button {
                        selectedFeature = feature
                    } label: {
                        Label(feature.title, systemImage: feature.systemImage)
                    }
                    .accessibilityIdentifier("sidebar.\(feature.rawValue)")
                }
            }
            .navigationTitle("BrassTune")
            .accessibilityIdentifier("shell.ipadSidebar")
        } detail: {
            NavigationStack {
                featureView(selectedFeature)
            }
        }
        .accessibilityIdentifier("shell.ipadSplit")
    }

    @ViewBuilder
    private func featureView(_ feature: NativeFeature) -> some View {
        switch feature {
        case .home:
            HomeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .practice:
            PracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, deterministicAudio: uiTestMode)
        case .score:
            ScorePracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .sessions:
            SessionsView()
        case .metronome:
            MetronomeView()
        case .analytics, .progress, .coach:
            AnalyticsView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, mode: feature)
        case .ensemble:
            EnsembleView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .settings, .account:
            SettingsView(onboardingPresented: $onboardingPresented)
        case .privacy:
            LegalDetailView(kind: .privacy)
        case .terms:
            LegalDetailView(kind: .terms)
        case .support:
            LegalDetailView(kind: .support)
        }
    }
}

private struct RestoringSessionView: View {
    var body: some View {
        BTScreen {
            BTHeroCard {
                ProgressView()
                BTSectionHeader(title: "Restoring BrassTune", subtitle: "Checking for a saved session before opening practice.")
            }
        }
        .accessibilityIdentifier("screen.restoring")
    }
}

private struct AuthGatewayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.btPalette) private var palette
    @State private var email = ""
    @State private var password = ""
    @State private var rawAppleNonce = ""

    var body: some View {
        NavigationStack {
            BTScreen {
                BTHeroCard {
                    VStack(alignment: .leading, spacing: BTSpacing.md) {
                        Text("BrassTune")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(palette.accent)
                        Text("Sign in to sync practice, or continue as guest for local tuning and recording.")
                            .font(.headline)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    BTThemeSelector()
                    if let message = model.accountUnavailableMessage {
                        BTGlassCapsule {
                            Label(message, systemImage: "person.crop.circle.badge.checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(palette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        model.continueAsGuest()
                    } label: {
                        Label("Continue as guest", systemImage: "play.fill")
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("auth.continueAsGuest")
                }

                if model.accountFeaturesEnabled {
                    BTCard {
                        BTSectionHeader(title: "Account", subtitle: "Use the same account you use on the web beta.")
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("auth.email")
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("auth.password")
                        HStack(spacing: BTSpacing.md) {
                            Button("Sign in") {
                                Task { await model.signIn(email: email, password: password) }
                            }
                            .buttonStyle(BTSecondaryButtonStyle())
                            .accessibilityIdentifier("auth.signIn")
                            Button("Create account") {
                                Task { await model.signUp(email: email, password: password) }
                            }
                            .buttonStyle(BTSecondaryButtonStyle())
                            .accessibilityIdentifier("auth.createAccount")
                        }
                        Button {
                            Task { await model.requestPasswordReset(email: email) }
                        } label: {
                            Label("Forgot password", systemImage: "envelope")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("auth.forgotPassword")
                        SignInWithAppleButton(.signIn) { request in
                            rawAppleNonce = AuthService.randomNonce()
                            request.requestedScopes = [.email]
                            request.nonce = AuthService.sha256(rawAppleNonce)
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .frame(height: 44)
                        .accessibilityIdentifier("auth.appleSignIn")
                    }
                }

                BTCard {
                    BTSectionHeader(title: "Policies and support")
                    NavigationLink("Privacy") { LegalDetailView(kind: .privacy) }
                    NavigationLink("Terms") { LegalDetailView(kind: .terms) }
                    NavigationLink("Support") { LegalDetailView(kind: .support) }
                }

                if let error = model.lastError {
                    BTStatusCard(title: "Status", message: error.localizedDescription, status: "Action needed", tint: palette.danger)
                }
            }
            .navigationTitle("Welcome")
        }
        .accessibilityIdentifier("screen.authGateway")
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken else {
                model.lastError = .authenticationFailed
                return
            }
            Task { await model.completeAppleSignIn(identityToken: identityToken, rawNonce: rawAppleNonce) }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                model.lastError = .appleSignInCancelled
            } else {
                model.lastError = .authenticationFailed
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.btPalette) private var palette
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTHeroCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        Text("BrassTune")
                            .font(.title.weight(.bold))
                        Text("Brass practice analytics for local guest takes and account-backed sync when enabled.")
                            .font(.subheadline)
                            .foregroundStyle(palette.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    BTStatusPill(text: model.authState.displayTitle, tint: palette.accent)
                        .accessibilityIdentifier("home.accountStatus")
                }
            }
            .accessibilityIdentifier("home.hero")

            Color.clear
                .frame(height: 96)
                .accessibilityHidden(true)

            BTQuickActionCard(title: "Practice", systemImage: "play.fill") {
                HStack(spacing: BTSpacing.md) {
                    BTMetricTile(title: "Instrument", value: instrumentName(model.selectedInstrumentId), detail: "Written pitch", tint: palette.accent)
                    BTMetricTile(title: "Reference", value: String(format: "%.1f", model.referencePitchHz), detail: "A4 Hz", tint: palette.secondaryAccent)
                }
                Button {
                    selectedTab = .practice
                    selectedFeature = .practice
                } label: {
                    Label("Start practice", systemImage: "play.fill")
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("home.startPractice")
            }

            if model.analyticsSnapshot.hasSessions {
                LatestSessionSummary()
            } else {
                BTEmptyState(
                    title: "No local takes yet",
                    message: "Record a practice take to create native session review and analytics.",
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
                        subtitle: "Choose your instrument and reference pitch. Live microphone mode requires iOS permission."
                    )
                    Picker("Instrument", selection: $model.selectedInstrumentId) {
                        instrumentPickerOptions()
                    }
                    Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                }

                BTCard {
                    BTSectionHeader(
                        title: "How BrassTune records",
                        subtitle: "Stable notes create pitch frames. Silence, low signal, and unstable pitch are excluded from scoring."
                    )
                    Button {
                        model.continueAsGuest()
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
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab
    let deterministicAudio: Bool

    var body: some View {
        BTScreen {
            PracticeTunerSection(model: model, audioEngine: model.audioEngine, deterministicAudio: deterministicAudio)
            MicrophoneSection(audioEngine: model.audioEngine)
            if !model.sessions.isEmpty {
                BTCard {
                    BTSectionHeader(title: "Saved take ready", subtitle: "Review the latest take or inspect local analytics derived from saved frames.")
                    VStack(spacing: BTSpacing.md) {
                        Button {
                            selectedTab = .sessions
                            selectedFeature = .sessions
                        } label: {
                            Label("Review sessions", systemImage: "music.note.list")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("practice.reviewSessions")

                        Button {
                            selectedTab = .more
                            selectedFeature = .analytics
                        } label: {
                            Label("View analytics", systemImage: "chart.bar.xaxis")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("practice.viewAnalytics")
                    }
                }
                .accessibilityIdentifier("practice.savedTakeActions")
            }
            BTCard {
                BTSectionHeader(
                    title: "Recording policy",
                    subtitle: "Normal practice uses the microphone and keeps source audio local. Cloud sync only runs for signed-in accounts when account services are configured."
                )
            }
        }
        .navigationTitle("Practice")
        .accessibilityIdentifier("screen.practice")
    }
}

private struct PracticeTunerSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audioEngine: NativeAudioEngine
    let deterministicAudio: Bool

    var body: some View {
        let frame = audioEngine.currentFrame
        let noteLabel = frame?.writtenNoteName.map { "\($0)\(frame?.writtenOctave ?? 0)" } ?? "No lock"
        let centsLabel = frame?.centsDeviation.map { String(format: "%+.1f cents", $0) } ?? "Silence or no stable pitch"
        let statusLabel = displayStatus(frame?.tuningStatus.rawValue ?? "ready")

        BTCard {
            HStack {
                BTSectionHeader(title: "Practice tuner", subtitle: audioEngine.inputActive ? "Mic live" : "Ready for input")
                Spacer()
                BTStatusPill(text: statusLabel, tint: statusTint(frame?.tuningStatus.rawValue))
                    .accessibilityIdentifier("practice.tuningStatus")
            }
            Text(noteLabel)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(BTTheme.accent)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("practice.note")
            Text(centsLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("practice.cents")
            Button {
                if audioEngine.recording {
                    model.stopPracticeRecording()
                } else {
                    Task { await model.startPracticeRecording(testInjection: deterministicAudio) }
                }
            } label: {
                Label(audioEngine.recording ? "Stop recording" : "Start recording", systemImage: audioEngine.recording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityIdentifier("practice.recordButton")
            Text(audioEngine.recording ? "Recording" : "Ready")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(audioEngine.recording ? BTTheme.secondaryAccent : .secondary)
                .accessibilityIdentifier("practice.recordingState")
        }
        .accessibilityIdentifier("practice.tunerCard")
    }
}

private struct MicrophoneSection: View {
    @ObservedObject var audioEngine: NativeAudioEngine

    var body: some View {
        BTCard {
            BTSectionHeader(
                title: "Microphone",
                subtitle: audioEngine.inputActive ? "Permission granted, input active, and samples are flowing." : "BrassTune requests microphone access only when recording or tuning."
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

struct MetronomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        BTScreen {
            BTCard {
                BTSectionHeader(title: "Metronome", subtitle: model.metronome.bleedPolicy)
                Stepper("BPM \(model.metronomeSettings.bpm)", value: bpmBinding, in: 20...300, step: 1)
                    .accessibilityIdentifier("metronome.bpmStepper")
                Stepper("Beats \(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit)", value: beatsBinding, in: 1...12, step: 1)
                    .accessibilityIdentifier("metronome.beatsStepper")
                Stepper("Subdivision \(model.metronomeSettings.subdivision)", value: subdivisionBinding, in: 1...8, step: 1)
                    .accessibilityIdentifier("metronome.subdivisionStepper")
                Toggle("Accent first beat", isOn: accentBinding)
                Toggle("Mute clicks", isOn: mutedBinding)
                HStack(spacing: BTSpacing.md) {
                    Button {
                        if model.metronome.running {
                            model.metronome.stop()
                        } else {
                            model.metronome.start(settings: model.metronomeSettings, recordingActive: model.audioEngine.recording)
                        }
                    } label: {
                        Label(model.metronome.running ? "Stop metronome" : "Start metronome", systemImage: model.metronome.running ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("metronome.toggle")
                    BTStatusPill(text: model.metronome.running ? "Beat \(model.metronome.currentBeat)" : "Stopped")
                }
            }
        }
        .navigationTitle("Metronome")
        .accessibilityIdentifier("screen.metronome")
    }

    private var bpmBinding: Binding<Int> {
        Binding(
            get: { model.metronomeSettings.bpm },
            set: { var settings = model.metronomeSettings; settings.bpm = $0; model.updateMetronomeSettings(settings) }
        )
    }

    private var beatsBinding: Binding<Int> {
        Binding(
            get: { model.metronomeSettings.beatsPerMeasure },
            set: { var settings = model.metronomeSettings; settings.beatsPerMeasure = $0; model.updateMetronomeSettings(settings) }
        )
    }

    private var subdivisionBinding: Binding<Int> {
        Binding(
            get: { model.metronomeSettings.subdivision },
            set: { var settings = model.metronomeSettings; settings.subdivision = $0; model.updateMetronomeSettings(settings) }
        )
    }

    private var accentBinding: Binding<Bool> {
        Binding(
            get: { model.metronomeSettings.accentFirstBeat },
            set: { var settings = model.metronomeSettings; settings.accentFirstBeat = $0; model.updateMetronomeSettings(settings) }
        )
    }

    private var mutedBinding: Binding<Bool> {
        Binding(
            get: { model.metronomeSettings.muted },
            set: { var settings = model.metronomeSettings; settings.muted = $0; model.updateMetronomeSettings(settings) }
        )
    }
}

struct ScorePracticeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab
    @State private var fileImporterPresented = false
    @State private var scannerPresented = false
    @State private var importedPhoto: PhotosPickerItem?
    @State private var importMessage: String?

    var body: some View {
        BTScreen {
            BTCard {
                BTSectionHeader(
                    title: "Score Practice",
                    subtitle: "Source pages stay local by default. Native review links pitch events to page and time; printed-note recognition remains user-confirmed."
                )
                HStack(spacing: BTSpacing.md) {
                    Button { fileImporterPresented = true } label: { Label("Import file", systemImage: "doc") }
                        .buttonStyle(BTSecondaryButtonStyle())
                    PhotosPicker(selection: $importedPhoto, matching: .images) {
                        Label("Photos", systemImage: "photo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BTSpacing.md)
                    }
                    .background(BTTheme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: BTGeneratedThemeTokens.radiusSmall, style: .continuous))
                    .accessibilityIdentifier("score.photos")
                }
                HStack(spacing: BTSpacing.md) {
                    Button { scannerPresented = true } label: { Label("Scan", systemImage: "camera") }
                        .buttonStyle(BTSecondaryButtonStyle())
                    Button {
                        selectedTab = .practice
                        selectedFeature = .practice
                    } label: { Label("Practice with tuner", systemImage: "gauge.with.dots.needle.67percent") }
                        .buttonStyle(BTPrimaryButtonStyle())
                }
                if let importMessage {
                    Text(importMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("score.importStatus")
                }
            }

            if model.scoreDocuments.isEmpty {
                BTEmptyState(title: "No score pages", message: "Import a PDF, image, photo, or scan to begin page-linked practice.", systemImage: "doc.viewfinder")
            } else {
                ForEach(model.scoreDocuments) { document in
                    BTCard {
                        HStack(alignment: .top) {
                            BTSectionHeader(title: document.name, subtitle: "\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") - \(document.sourceKind.title)")
                            Spacer()
                            BTStatusPill(text: "Local")
                        }
                        Text(document.reviewNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Markers: \(document.markers.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            model.deleteScoreDocument(id: document.id)
                        } label: {
                            Label("Remove score", systemImage: "trash")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                    }
                }
            }
        }
        .navigationTitle("Score")
        .accessibilityIdentifier("screen.scorePractice")
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.pdf, .png, .jpeg, .image],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .sheet(isPresented: $scannerPresented) {
            DocumentScannerView { pageCount in
                model.addScoreDocument(name: "Camera scan", kind: .camera, pageCount: pageCount)
                importMessage = "Camera scan added locally with \(pageCount) page\(pageCount == 1 ? "" : "s")."
            } onUnavailable: {
                importMessage = "Camera scanning is unavailable on this device or simulator."
            }
        }
        .onChange(of: importedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    model.addScoreDocument(name: "Photo import", kind: .photos, pageCount: 1)
                    importMessage = "Photo added locally for score practice."
                } else {
                    importMessage = "Photo import could not be read."
                }
                importedPhoto = nil
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importMessage = "No score file was selected."
                return
            }
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard fileSize <= 25 * 1024 * 1024 else {
                importMessage = "That score file is larger than the 25 MB native import limit."
                return
            }
            let type = UTType(filenameExtension: url.pathExtension.lowercased())
            if type?.conforms(to: .pdf) == true {
                let pageCount = PDFDocument(url: url)?.pageCount ?? 1
                guard pageCount <= 64 else {
                    importMessage = "That PDF has more than the 64-page native review limit."
                    return
                }
                model.addScoreDocument(name: url.lastPathComponent, kind: .pdf, pageCount: pageCount)
                importMessage = "PDF added locally with \(pageCount) page\(pageCount == 1 ? "" : "s")."
            } else if type?.conforms(to: .image) == true {
                model.addScoreDocument(name: url.lastPathComponent, kind: .image, pageCount: 1)
                importMessage = "Image added locally for score practice."
            } else {
                importMessage = "That file type is not supported for native score practice."
            }
        case .failure:
            importMessage = "Score import was cancelled or could not be read."
        }
    }
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: (Int) -> Void
    let onUnavailable: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard VNDocumentCameraViewController.isSupported else {
            DispatchQueue.main.async {
                onUnavailable()
                dismiss()
            }
            return UIViewController()
        }
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pageCount = scan.pageCount
            DispatchQueue.main.async { [parent] in
                parent.onComplete(pageCount)
                parent.dismiss()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            DispatchQueue.main.async { [parent] in
                parent.dismiss()
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            DispatchQueue.main.async { [parent] in
                parent.onUnavailable()
                parent.dismiss()
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
                subtitle: "Local microphone takes are available for review, playback, export, and deletion."
            )
            if model.sessions.isEmpty {
                BTEmptyState(title: "No saved sessions", message: "Stop a practice recording to create a local review session.", systemImage: "tray")
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
                    BTSectionHeader(title: "Relisten", subtitle: session.retainedRecordingURL == nil ? "No playback file is available for this take." : "Playback is ready from local storage.")
                    if let url = session.retainedRecordingURL {
                        Button {
                            if model.audioEngine.playbackActive {
                                model.audioEngine.stopPlayback()
                            } else {
                                model.audioEngine.play(url: url)
                            }
                        } label: {
                            Label(model.audioEngine.playbackActive ? "Stop playback" : "Play recording", systemImage: model.audioEngine.playbackActive ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("session.playbackButton")
                    }
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
                    BTSectionHeader(title: "Delete", subtitle: "Removes this local session and retained recording from the native app.")
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
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab
    var mode: NativeFeature = .analytics

    var body: some View {
        let snapshot = model.analyticsSnapshot
        BTScreen {
            BTSectionHeader(
                title: mode.title,
                subtitle: snapshot.hasSessions ? "Derived from local recorded takes saved on this device." : "Record a local take before BrassTune can calculate measured guidance."
            )
            if snapshot.hasSessions {
                BTCard {
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "Sessions", value: "\(snapshot.sessionCount)", detail: "\(snapshot.validFrameCount) valid frames")
                        BTMetricTile(title: "Avg abs", value: String(format: "%.1f", snapshot.averageAbsCents), detail: "cents", tint: BTTheme.secondaryAccent)
                    }
                    HStack(spacing: BTSpacing.md) {
                        BTMetricTile(title: "In tune", value: "\(String(format: "%.0f", snapshot.averageInTunePercentage))%", detail: "all local frames", tint: BTTheme.success)
                        BTMetricTile(title: "Practice", value: "\(String(format: "%.0f", snapshot.totalPracticeSeconds))s", detail: "recorded duration")
                    }
                }
                .accessibilityIdentifier("analytics.metrics")

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
                    Button {
                        selectedTab = .sessions
                        selectedFeature = .sessions
                    } label: {
                        Label("Review sessions", systemImage: "music.note.list")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("analytics.reviewSessions")
                }
            } else {
                BTEmptyState(
                    title: "\(mode.title) needs local sessions",
                    message: "Record a practice take to calculate in-tune percentage, average cents, progress, and recommendations on device.",
                    systemImage: mode.systemImage
                )
                .accessibilityIdentifier("analytics.empty")
                Button {
                    selectedTab = .practice
                    selectedFeature = .practice
                } label: {
                    Label("Record practice take", systemImage: "record.circle")
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityIdentifier("analytics.recordSample")
            }
        }
        .navigationTitle(mode.title)
        .accessibilityIdentifier("screen.analytics")
    }
}

struct EnsembleView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab

    var body: some View {
        BTScreen {
            BTSectionHeader(
                title: "Ensemble",
                subtitle: "Memberships and teacher assignments require an account-backed workspace."
            )
            switch model.authState {
            case .guest:
                AccountRequiredCard(
                    title: "Account-backed workspace",
                    message: model.accountUnavailableMessage ?? "Sign in to load ensemble memberships from your teacher or organization.",
                    actionTitle: "Open Settings",
                    action: { openSettings() }
                )
                .accessibilityIdentifier("ensemble.accountRequired")
            case .signedOut:
                AccountRequiredCard(
                    title: "Account required",
                    message: model.accountUnavailableMessage ?? "Sign in to load ensemble memberships from your teacher or organization.",
                    actionTitle: "Open Settings",
                    action: { openSettings() }
                )
                .accessibilityIdentifier("ensemble.accountRequired")
            case .emailConfirmationRequired(let email):
                AccountRequiredCard(
                    title: "Confirm email",
                    message: "Confirm \(email) before BrassTune can load account-backed ensemble memberships.",
                    actionTitle: "Open Settings",
                    action: { openSettings() }
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

    private func openSettings() {
        selectedTab = .more
        selectedFeature = .settings
    }
}

struct MoreView: View {
    @Binding var selectedFeature: NativeFeature
    @Binding var selectedTab: AppTab
    @Binding var onboardingPresented: Bool

    private let moreFeatures: [NativeFeature] = [
        .metronome, .analytics, .progress, .coach, .ensemble, .settings, .account, .privacy, .terms, .support
    ]

    var body: some View {
        BTScreen {
            BTSectionHeader(title: "More", subtitle: "Additional practice, account, legal, and support surfaces.")
            ForEach(moreFeatures) { feature in
                NavigationLink {
                    moreDestination(feature)
                } label: {
                    BTGlassCapsule {
                        Label(feature.title, systemImage: feature.systemImage)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("more.\(feature.rawValue)")
            }
        }
        .navigationTitle("More")
        .accessibilityIdentifier("screen.more")
    }

    @ViewBuilder
    private func moreDestination(_ feature: NativeFeature) -> some View {
        switch feature {
        case .metronome:
            MetronomeView()
        case .analytics, .progress, .coach:
            AnalyticsView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, mode: feature)
        case .ensemble:
            EnsembleView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .settings, .account:
            SettingsView(onboardingPresented: $onboardingPresented)
        case .privacy:
            LegalDetailView(kind: .privacy)
        case .terms:
            LegalDetailView(kind: .terms)
        case .support:
            LegalDetailView(kind: .support)
        case .home:
            HomeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .practice:
            PracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab, deterministicAudio: false)
        case .score:
            ScorePracticeView(selectedFeature: $selectedFeature, selectedTab: $selectedTab)
        case .sessions:
            SessionsView()
        }
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
