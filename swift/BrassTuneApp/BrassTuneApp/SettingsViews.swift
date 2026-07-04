import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var onboardingPresented: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var deletionConfirmation = ""
    @State private var localDataConfirmation = ""
    @State private var rawAppleNonce = ""

    private var accountActionsEnabled: Bool {
        model.accountFeaturesEnabled
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
                if let accountUnavailableMessage = model.accountUnavailableMessage {
                    Text(accountUnavailableMessage)
                        .font(.footnote)
                        .foregroundStyle(BTTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.accountDisabledMessage")
                }
            }

            BTCard {
                BTSectionHeader(title: "Tuner", subtitle: "Instrument and reference pitch affect local sample takes.")
                Picker("Instrument", selection: $model.selectedInstrumentId) {
                    instrumentPickerOptions()
                }
                .accessibilityIdentifier("settings.instrumentPicker")
                Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                    .accessibilityIdentifier("settings.referencePitchStepper")
                Button {
                    onboardingPresented = true
                } label: {
                    Label("Reopen onboarding", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("settings.reopenOnboarding")
            }

            BTCard {
                BTSectionHeader(title: "Metronome defaults", subtitle: "These settings also drive the floating recording controls.")
                Stepper("BPM \(model.metronome.bpm)", value: Binding(get: { model.metronome.bpm }, set: { model.setTempo($0) }), in: 30...240, step: 1)
                    .accessibilityIdentifier("settings.metronomeBPM")
                Picker("Subdivision", selection: Binding(get: { model.metronome.subdivision }, set: { model.metronome.subdivision = $0 })) {
                    ForEach(MetronomeSubdivision.allCases) { subdivision in
                        Text(subdivision.title).tag(subdivision)
                    }
                }
                .accessibilityIdentifier("settings.metronomeSubdivision")
                Toggle("Visual-only by default", isOn: Binding(get: { model.metronome.visualOnly }, set: { model.setMetronomeVisualOnly($0) }))
                    .accessibilityIdentifier("settings.metronomeVisualOnly")
            }

            if accountActionsEnabled {
                BTCard {
                    BTSectionHeader(title: "Sign in", subtitle: "Use beta account email or Apple sign-in.")
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
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("settings.signIn")

                        Button("Create account") {
                            Task { await model.signUp(email: email, password: password) }
                        }
                        .buttonStyle(BTSecondaryButtonStyle())
                        .accessibilityIdentifier("settings.createAccount")
                    }
                    Button {
                        Task { await model.requestPasswordReset(email: email) }
                    } label: {
                        Label("Send password reset", systemImage: "envelope")
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
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
            } else {
                BTCard {
                    BTSectionHeader(title: "Guest mode", subtitle: "Cloud accounts are hidden because provider configuration is not present in this native beta.")
                    Button("Continue as guest") {
                        model.enterGuestDemo()
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("settings.continueAsGuest")
                }
            }

            BTCard {
                BTSectionHeader(title: "Session", subtitle: "Sign out affects account state; local practice data can be cleared separately below.")
                Button("Sign out") {
                    model.signOut()
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("settings.signOut")
            }

            BTCard {
                BTSectionHeader(title: "Data", subtitle: "Export local practice summaries or clear sessions and scores on this device.")
                ShareLink(item: model.exportDataText()) {
                    Label("Export local data", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("settings.exportData")

                TextField("Type clear local data", text: $localDataConfirmation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.localDataConfirmation")

                Button(role: .destructive) {
                    model.clearLocalPracticeData()
                } label: {
                    Label("Clear local practice data", systemImage: "trash")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .disabled(localDataConfirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "clear local data")
                .accessibilityIdentifier("settings.clearLocalData")

                TextField("Type delete my account", text: $deletionConfirmation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.deletionConfirmation")
                Text(deletionHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    Task { await model.deleteAccount(confirmation: deletionConfirmation) }
                } label: {
                    Label(deleteButtonTitle, systemImage: "trash")
                }
                .buttonStyle(BTSecondaryButtonStyle())
                .accessibilityIdentifier("settings.deleteAccount")
            }

            BTCard {
                BTSectionHeader(title: "Legal and support", subtitle: "Release-critical policy and support surfaces are available in-app.")
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
                BTSectionHeader(title: "About", subtitle: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"). Scores and sample sessions are local unless you explicitly share/export.")
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
    }

    private var accountStatusMessage: String {
        switch model.authState {
        case .guest:
            return "Guest practice is active. Local practice data remains on this device."
        case .signedOut:
            return "Signed out. Account-backed features require sign-in."
        case .signedIn(let email):
            return "Signed in as \(email)."
        case .emailConfirmationRequired(let email):
            return "Check \(email) to confirm the account before account-backed features load."
        }
    }

    private var deleteButtonTitle: String {
        model.authState.usesRemoteAccount ? "Delete account" : "Clear local account data"
    }

    private var deletionHelpText: String {
        if model.authState.usesRemoteAccount {
            return "Deletion sends the account request to cloud sync when an account session is available, then clears local sessions and credentials."
        }
        return "No remote account is active. The confirmation clears local sessions, demo ensemble state, and stored credentials on this device."
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
    let identifier: String
    let destination: Destination

    init(title: String, systemImage: String, identifier: String, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
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
                        "BrassTune uses account, practice, pitch, recommendation, ensemble, export, and optional recording data to provide tuning feedback and account lifecycle controls.",
                        "Local score imports and sample-session data stay on this device unless you explicitly share or export them. The native beta does not upload copyrighted scores by default.",
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
                        "Include the affected screen, approximate time of the issue, account state, and whether the take was a sample or microphone session.",
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
