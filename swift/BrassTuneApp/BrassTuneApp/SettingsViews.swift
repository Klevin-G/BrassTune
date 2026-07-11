import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var onboardingPresented: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var rawAppleNonce = ""
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var advancedTunerExpanded = false

    private var accountActionsEnabled: Bool {
        model.accountFeaturesEnabled
    }

    private enum DestructiveAction: String, Identifiable {
        case clearPracticeData
        case deleteAccount

        var id: String { rawValue }
    }

    var body: some View {
        BTScreen {
            BTCard {
                HStack {
                    BTSectionHeader(title: "Account", subtitle: accountStatusMessage)
                    Spacer()
                    BTStatusPill(text: model.authState.displayTitle, tint: model.authState.usesRemoteAccount ? BTTheme.success : BTTheme.warning)
                        .accessibilityIdentifier("settings.accountStatus")
                }
            }

            BTCard {
                BTSectionHeader(title: "Tuner", subtitle: "Choose the instrument you play.")
                Picker("Instrument", selection: $model.selectedInstrumentId) {
                    instrumentPickerOptions()
                }
                .accessibilityIdentifier("settings.instrumentPicker")

                Button {
                    withAnimation { advancedTunerExpanded.toggle() }
                } label: {
                    HStack {
                        Label("Advanced tuner settings", systemImage: "tuningfork")
                            .font(.headline)
                        Spacer()
                        Image(systemName: advancedTunerExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.advancedTunerSettings")

                if advancedTunerExpanded {
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        Text("Most bands use A4 = 440 Hz. Change this only if your director asks you to.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                            .accessibilityIdentifier("settings.referencePitchStepper")
                    }
                    .padding(.top, BTSpacing.sm)
                }

                Button {
                    onboardingPresented = true
                } label: {
                    Label("Replay welcome", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.reopenOnboarding")
            }

            BTCard {
                BTSectionHeader(title: "Metronome defaults", subtitle: "Choose the beat you want when the metronome opens.")
                Stepper("Tempo: \(model.metronome.bpm) BPM", value: Binding(get: { model.metronome.bpm }, set: { model.setTempo($0) }), in: 30...240, step: 1)
                    .accessibilityIdentifier("settings.metronomeBPM")
                Picker("Meter", selection: Binding(get: { model.metronome.beatsPerMeasure }, set: { model.setMeter(beats: $0) })) {
                    ForEach([2, 3, 4, 5, 6, 7, 9, 12], id: \.self) { beats in
                        Text("\(beats)/\(model.metronome.beatUnit)").tag(beats)
                    }
                }
                .accessibilityIdentifier("settings.metronomeMeter")
                Picker("Subdivision", selection: Binding(get: { model.metronome.subdivision }, set: { model.metronome.subdivision = $0 })) {
                    ForEach(MetronomeSubdivision.allCases) { subdivision in
                        Text(subdivision.title).tag(subdivision)
                    }
                }
                .accessibilityIdentifier("settings.metronomeSubdivision")

                Toggle("Play sound", isOn: Binding(
                    get: { !model.metronome.visualOnly },
                    set: { enabled in
                        model.setMetronomeVolume(enabled ? max(0.6, model.metronome.volume) : 0)
                    }
                ))
                .accessibilityIdentifier("settings.metronomeSound")

                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text("Volume")
                        .font(.subheadline.weight(.semibold))
                    Slider(
                        value: Binding(get: { model.metronome.volume }, set: { model.setMetronomeVolume($0) }),
                        in: 0.1...1
                    )
                    .disabled(model.metronome.visualOnly)
                    .accessibilityIdentifier("settings.metronomeVolume")
                }

                SettingsNavigationRow(title: "Open metronome", systemImage: "metronome", identifier: "settings.metronomeLink") {
                    MetronomeView()
                }
            }

            BTCard {
                BTSectionHeader(title: "Practice library", subtitle: "Add and organize scores for practice.")
                SettingsNavigationRow(
                    title: "Sheet music",
                    systemImage: "music.note.list",
                    detail: "\(model.scores.count)",
                    identifier: "settings.scoresLink"
                ) {
                    ScorePracticeView()
                }
            }

            if accountActionsEnabled && !model.authState.usesRemoteAccount {
                BTCard {
                    BTSectionHeader(title: "Sign in", subtitle: "Use your email or Apple account.")
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.email")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.password")
                    HStack(spacing: BTSpacing.md) {
                        Button("Sign in") {
                            Task { await model.signIn(email: email, password: password) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.signIn")

                        Button("Create account") {
                            Task { await model.signUp(email: email, password: password) }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.createAccount")
                    }
                    Button {
                        Task { await model.requestPasswordReset(email: email) }
                    } label: {
                        Label("Send password reset", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.passwordReset")
                    SignInWithAppleButton(.signIn) { request in
                        rawAppleNonce = AuthService.randomNonce()
                        request.requestedScopes = [.email]
                        request.nonce = AuthService.sha256(rawAppleNonce)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .frame(height: 44)
                    .accessibilityIdentifier("settings.appleSignIn")
                }
            } else if !accountActionsEnabled {
                BTCard {
                    BTSectionHeader(title: "Guest mode", subtitle: "You're practicing as a guest. Your data stays on this device.")
                    if model.authState != .guest {
                        Button {
                            model.enterGuestDemo()
                        } label: {
                            Label("Continue as guest", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings.continueAsGuest")
                    }
                }
            }

            if model.authState.usesRemoteAccount {
                BTCard {
                    BTSectionHeader(title: "Sign out", subtitle: "Your practice history stays on this device.")
                    Button {
                        model.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.signOut")
                }
            }

            BTCard {
                BTSectionHeader(title: "Your data", subtitle: "Export a copy or remove saved data.")
                ShareLink(item: model.exportDataText()) {
                    Label("Export local data", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.exportData")

                Button(role: .destructive) {
                    pendingDestructiveAction = .clearPracticeData
                } label: {
                    Label("Clear local practice data", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.clearLocalData")

                Text(deletionHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    pendingDestructiveAction = .deleteAccount
                } label: {
                    Label(deleteButtonTitle, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.deleteAccount")
            }

            BTCard {
                BTSectionHeader(title: "Legal and support", subtitle: "Privacy, terms, and help.")
                SettingsNavigationRow(title: "Privacy Policy", systemImage: "hand.raised", identifier: "settings.privacyLink") {
                    LegalDetailView(kind: .privacy)
                }
                SettingsNavigationRow(title: "Terms of Service", systemImage: "doc.text", identifier: "settings.termsLink") {
                    LegalDetailView(kind: .terms)
                }
                SettingsNavigationRow(title: "Support", systemImage: "questionmark.circle", identifier: "settings.supportLink") {
                    LegalDetailView(kind: .support)
                }
            }

            BTCard {
                BTSectionHeader(title: "About", subtitle: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            }

            if let error = model.lastError {
                BTCard {
                    BTSectionHeader(title: "Status", subtitle: error.localizedDescription)
                }
                .accessibilityIdentifier("settings.status")
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(destructiveAlertTitle(for: action)),
                message: Text(destructiveAlertMessage(for: action)),
                primaryButton: .destructive(Text(destructiveButtonTitle(for: action))) {
                    performDestructiveAction(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var accountStatusMessage: String {
        switch model.authState {
        case .guest:
            return "You're practicing as a guest. Your data stays on this device."
        case .signedOut:
            return "You're signed out. Your practice data is still on this device."
        case .signedIn(let email):
            return "Signed in as \(email)."
        case .emailConfirmationRequired(let email):
            return "Check \(email) to finish signing in."
        }
    }

    private var deleteButtonTitle: String {
        model.authState.usesRemoteAccount ? "Delete account" : "Clear all app data"
    }

    private var deletionHelpText: String {
        if model.authState.usesRemoteAccount {
            return "Deleting your account also removes practice history and sheet music saved on this device."
        }
        return "This removes practice history, sheet music, and saved sign-in information from this device."
    }

    private func destructiveAlertTitle(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return "Delete practice data?"
        case .deleteAccount:
            return model.authState.usesRemoteAccount ? "Delete your account?" : "Clear all app data?"
        }
    }

    private func destructiveAlertMessage(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return "All practice history and imported sheet music on this device will be deleted. This can't be undone."
        case .deleteAccount:
            if model.authState.usesRemoteAccount {
                return "Your account, saved sign-in, practice history, and imported sheet music will be deleted. This can't be undone."
            }
            return "Practice history, imported sheet music, and saved sign-in information will be deleted from this device. This can't be undone."
        }
    }

    private func destructiveButtonTitle(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return "Delete practice data"
        case .deleteAccount:
            return model.authState.usesRemoteAccount ? "Delete account" : "Clear all data"
        }
    }

    private func performDestructiveAction(_ action: DestructiveAction) {
        switch action {
        case .clearPracticeData:
            model.clearLocalPracticeData()
        case .deleteAccount:
            Task { await model.deleteAccount() }
        }
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

private struct SettingsNavigationRow<Destination: View>: View {
    let title: String
    let systemImage: String
    let detail: String?
    let identifier: String
    let destination: Destination

    init(title: String, systemImage: String, detail: String? = nil, identifier: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.identifier = identifier
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: BTSpacing.md) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, BTSpacing.sm)
        }
        .accessibilityIdentifier(identifier)
    }
}

enum LegalKind {
    case privacy
    case terms
    case support
}

struct LegalDetailView: View {
    let kind: LegalKind

    var body: some View {
        BTScreen {
            switch kind {
            case .privacy:
                LegalCard(
                    title: "Privacy Policy",
                    messages: [
                        "BrassTune uses account and practice data to provide tuning feedback and saved progress.",
                        "Practice recordings and imported sheet music stay on this device unless you choose to share or export them.",
                    ]
                )
            case .terms:
                LegalCard(
                    title: "Terms of Service",
                    messages: [
                        "Use BrassTune only with consent and within the policies of the school, studio, or organization providing access.",
                        "BrassTune is practice analytics software and does not replace instruction or hearing-safety guidance.",
                    ]
                )
            case .support:
                LegalCard(
                    title: "Support",
                    messages: [
                        "Contact the teacher, director, or organization that provided BrassTune access.",
                        "Tell them what you were doing, which screen you were on, and about when the problem happened.",
                    ]
                )
            }
        }
        .navigationTitle(title)
        .accessibilityIdentifier("screen.legal.\(title)")
    }

    private var title: String {
        switch kind {
        case .privacy: return "Privacy"
        case .terms: return "Terms"
        case .support: return "Support"
        }
    }
}

private struct LegalCard: View {
    let title: String
    let messages: [String]

    var body: some View {
        BTCard {
            BTSectionHeader(title: title)
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
