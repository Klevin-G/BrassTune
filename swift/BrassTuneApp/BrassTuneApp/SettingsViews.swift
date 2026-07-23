import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var onboardingPresented: Bool
    @State private var authMode: GatewayAuthMode?
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
                    BTSectionHeader(title: "Account", subtitle: .verbatim(accountStatusMessage))
                    Spacer()
                    BTStatusPill(text: .verbatim(model.authState.displayTitle), tint: model.authState.usesRemoteAccount ? BTTheme.success : BTTheme.warning)
                        .accessibilityIdentifier("settings.accountStatus")
                }
                if let notice = model.authNotice {
                    Label { Text(verbatim: notice) } icon: { Image(systemName: model.authNoticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(model.authNoticeIsError ? BTTheme.danger : BTTheme.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.authNotice")
                }

                if accountActionsEnabled && !model.authState.usesRemoteAccount {
                    Button {
                        authMode = .signIn
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("settings.signIn")

                    Button {
                        authMode = .createAccount
                    } label: {
                        Label("Create account", systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTSecondaryButtonStyle())
                    .accessibilityIdentifier("settings.createAccount")

                    NativeAppleSignInButton(identifier: "settings.appleSignIn")
                } else if !accountActionsEnabled {
                    Text(verbatim: model.accountUnavailableMessage ?? NativeLocalization.string("Online accounts aren't configured in this build. You can still practice as a guest, and your data stays on this device."))
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.accountConfigurationUnavailable")
                }

                if model.authState.usesRemoteAccount {
                    Button {
                        Task { await model.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.signOut")
                }
            }

            BTCard {
                BTSectionHeader(title: "Tuner", subtitle: "Choose the instrument you play.")
                Picker("Instrument", selection: $model.selectedInstrumentId) {
                    instrumentPickerOptions()
                }
                .accessibilityIdentifier("settings.instrumentPicker")

                Button {
                    if reduceMotion {
                        advancedTunerExpanded.toggle()
                    } else {
                        withAnimation { advancedTunerExpanded.toggle() }
                    }
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
                .btMinimumInteractiveSize(alignment: .leading)
                .accessibilityIdentifier("settings.advancedTunerSettings")

                if advancedTunerExpanded {
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        Text("Most bands use A4 = 440 Hz. Change this only if your director asks you to.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Stepper(value: $model.referencePitchHz, in: 430...450, step: 0.5) {
                            Text(verbatim: NativeLocalization.format("A4 %@ Hz", String(format: "%.1f", model.referencePitchHz)))
                        }
                            .accessibilityIdentifier("settings.referencePitchStepper")
                    }
                    .padding(.top, BTSpacing.sm)
                }

                Button {
                    onboardingPresented = true
                } label: {
                    Label("Review instrument setup", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.reopenOnboarding")
            }

            BTCard {
                BTSectionHeader(title: "Language", subtitle: "Follow the system language or choose a BrassTune language explicitly.")
                Picker("Language", selection: $model.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }
                .accessibilityIdentifier("settings.languagePicker")
            }

            BTCard {
                BTSectionHeader(
                    title: "Feedback",
                    subtitle: "Choose whether BrassTune gives a subtle confirmation after saving practice."
                )
                Toggle("Success haptics", isOn: $model.successHapticsEnabled)
                    .accessibilityIdentifier("settings.successHaptics")
                Text("Reduce Motion also suppresses this feedback. Every saved result still includes a visible icon and text.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BTCard {
                BTSectionHeader(title: "Tools")
                SettingsNavigationRow(title: "Metronome", systemImage: "metronome", identifier: "settings.metronomeLink") {
                    MetronomeView()
                }
                SettingsNavigationRow(
                    title: "Sheet music",
                    systemImage: "music.note.list",
                    detail: NativeLocalization.isolate(String(model.scores.count)),
                    identifier: "settings.scoresLink"
                ) {
                    ScorePracticeView()
                }
                SettingsNavigationRow(
                    title: "Offline practice packs",
                    systemImage: "shippingbox",
                    detail: NativeLocalization.isolate(String(model.practicePacks.count)),
                    identifier: "settings.practicePacksLink"
                ) {
                    PracticePacksView()
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

                Text(verbatim: deletionHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    pendingDestructiveAction = .deleteAccount
                } label: {
                    Label { Text(verbatim: deleteButtonTitle) } icon: { Image(systemName: "trash") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.authOperationInProgress)
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
                Text(verbatim: NativeLocalization.format(
                    "Version %@ (%@)",
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                    Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                ))
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
            }

            if let error = model.lastError {
                BTCard {
                    BTSectionHeader(title: "Status", subtitle: .verbatim(error.localizedDescription))
                }
                .accessibilityIdentifier("settings.status")
            }
        }
        .controlSize(.large)
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
        .sheet(item: $authMode) { mode in
            GatewayAuthForm(mode: mode)
        }
        .alert(item: $pendingDestructiveAction) { action in
            Alert(
                title: Text(verbatim: destructiveAlertTitle(for: action)),
                message: Text(verbatim: destructiveAlertMessage(for: action)),
                primaryButton: .destructive(Text(verbatim: destructiveButtonTitle(for: action))) {
                    performDestructiveAction(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var accountStatusMessage: String {
        switch model.authState {
        case .guest:
            return NativeLocalization.string("You're practicing as a guest. Your data stays on this device.")
        case .signedOut:
            return NativeLocalization.string("You're signed out. Your practice data is still on this device.")
        case .signedIn(let email):
            return NativeLocalization.format("Signed in as %@.", email)
        case .emailConfirmationRequired(let email):
            return NativeLocalization.format("Check %@ to finish signing in.", email)
        }
    }

    private var deleteButtonTitle: String {
        NativeLocalization.string(model.authState.usesRemoteAccount ? "Delete account" : "Clear all app data")
    }

    private var deletionHelpText: String {
        if model.authState.usesRemoteAccount {
            return NativeLocalization.string("Deleting your account also removes practice history and sheet music saved on this device.")
        }
        return NativeLocalization.string("This removes practice history, sheet music, and saved sign-in information from this device.")
    }

    private func destructiveAlertTitle(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return NativeLocalization.string("Delete practice data?")
        case .deleteAccount:
            return NativeLocalization.string(model.authState.usesRemoteAccount ? "Delete your account?" : "Clear all app data?")
        }
    }

    private func destructiveAlertMessage(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return NativeLocalization.string("All practice history and imported sheet music on this device will be deleted. This can't be undone.")
        case .deleteAccount:
            if model.authState.usesRemoteAccount {
                return NativeLocalization.string("Your account, saved sign-in, practice history, and imported sheet music will be deleted. This can't be undone.")
            }
            return NativeLocalization.string("Practice history, imported sheet music, and saved sign-in information will be deleted from this device. This can't be undone.")
        }
    }

    private func destructiveButtonTitle(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return NativeLocalization.string("Delete practice data")
        case .deleteAccount:
            return NativeLocalization.string(model.authState.usesRemoteAccount ? "Delete account" : "Clear all data")
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

}

struct NativeAppleSignInButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var rawAppleNonce = ""
    let identifier: String

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            rawAppleNonce = AuthService.randomNonce()
            request.requestedScopes = [.email]
            request.nonce = AuthService.sha256(rawAppleNonce)
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .disabled(model.authOperationInProgress || !model.accountFeaturesEnabled)
        .accessibilityIdentifier(identifier)
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

struct ClassesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var joinCode = ""
    @State private var pendingLeave: EnsembleSummary?
    @State private var authMode: GatewayAuthMode?

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Classes",
                title: "Your classes",
                subtitle: "Join more than one class, switch between them, or leave a class without changing your practice setup."
            )

            if model.testFixturesEnabled || model.authState.usesRemoteAccount {
                joinCard
                membershipContent
            } else {
                BTCard {
                    BTSectionHeader(
                        title: "Sign in to use classes",
                        subtitle: "Sign in before using classes."
                    )
                    Button {
                        authMode = .signIn
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BTPrimaryButtonStyle())
                    .accessibilityIdentifier("classes.signIn")

                    NativeAppleSignInButton(identifier: "classes.appleSignIn")
                }
                .accessibilityIdentifier("classes.signInRequired")
            }

            if let message = model.ensembleStatusMessage {
                BTCard(tint: BTTheme.surfaceWarm) {
                    Label { Text(verbatim: message) } icon: { Image(systemName: "checkmark.circle.fill") }
                        .foregroundStyle(BTTheme.success)
                }
                .accessibilityIdentifier("classes.status")
            }

            if (model.testFixturesEnabled || model.authState.usesRemoteAccount),
               let error = model.lastError {
                BTCard {
                    Text(verbatim: error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(BTTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("classes.error")
            }
        }
        .controlSize(.large)
        .navigationTitle("Classes")
        .accessibilityIdentifier("screen.classes")
        .task(id: model.authState.usesRemoteAccount) {
            guard model.testFixturesEnabled || model.authState.usesRemoteAccount else { return }
            await model.loadEnsembles()
        }
        .refreshable {
            guard model.testFixturesEnabled || model.authState.usesRemoteAccount else { return }
            await model.loadEnsembles()
        }
        .sheet(item: $authMode) { mode in
            GatewayAuthForm(mode: mode)
        }
        .alert(item: $pendingLeave) { ensemble in
            Alert(
                title: Text(verbatim: NativeLocalization.format("Leave %@?", ensemble.name)),
                message: Text("Your other classes and practice history will stay available."),
                primaryButton: .destructive(Text("Leave class")) {
                    Task { await model.leaveEnsemble(id: ensemble.id) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var joinCard: some View {
        BTCard {
            BTSectionHeader(title: "Join another class", subtitle: "Enter the code your teacher shared.")
            TextField("Class code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("classes.joinCode")
            Button {
                Task {
                    if await model.joinEnsemble(code: joinCode) {
                        joinCode = ""
                    }
                }
            } label: {
                Label { Text(verbatim: NativeLocalization.string(model.ensembleMutationInProgress ? "Joining…" : "Join class")) } icon: { Image(systemName: "person.badge.plus") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .disabled(model.ensembleMutationInProgress || joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("classes.join")
        }
    }

    @ViewBuilder
    private var membershipContent: some View {
        if model.ensemblesLoading && model.ensembles.isEmpty {
            BTCard {
                ProgressView("Loading classes…")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("classes.loading")
        } else if model.ensembles.isEmpty {
            BTEmptyState(
                title: "No classes yet",
                message: "Joining a class won't change your tuner, instrument, or practice history.",
                systemImage: "person.3"
            )
            .accessibilityIdentifier("classes.empty")
        } else {
            BTCard {
                BTSectionHeader(title: "Active class", subtitle: "Switching only changes which class is selected here.")
                Picker("Active class", selection: Binding(
                    get: { model.selectedEnsembleID ?? model.ensembles[0].id },
                    set: { model.selectedEnsembleID = $0 }
                )) {
                    ForEach(model.ensembles) { ensemble in
                        Text(verbatim: ensemble.name).tag(ensemble.id)
                    }
                }
                .accessibilityIdentifier("classes.activePicker")
            }

            ForEach(model.ensembles) { ensemble in
                BTCard(tint: model.selectedEnsembleID == ensemble.id ? BTTheme.surfaceWarm : BTTheme.surface) {
                    HStack(alignment: .top, spacing: BTSpacing.md) {
                        VStack(alignment: .leading, spacing: BTSpacing.xs) {
                            Text(verbatim: ensemble.name)
                                .font(.headline)
                            Text(verbatim: ensemble.viewerRoleLabel)
                                .font(.subheadline)
                                .foregroundStyle(BTTheme.muted)
                        }
                        Spacer()
                        if model.selectedEnsembleID == ensemble.id {
                            BTStatusPill(text: "Selected", tint: BTTheme.success)
                        }
                    }

                    if ensemble.canLeave {
                        Button(role: .destructive) {
                            pendingLeave = ensemble
                        } label: {
                            Label("Leave class", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .btMinimumInteractiveSize()
                        .disabled(model.ensembleMutationInProgress)
                        .accessibilityIdentifier("classes.leave.\(ensemble.id)")
                    } else {
                        Text(verbatim: NativeLocalization.string(ensemble.viewerCanManage
                            ? "Manage this class from its director tools."
                            : "This class role cannot leave through self-service."))
                            .font(.footnote)
                            .foregroundStyle(BTTheme.muted)
                    }
                }
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
                Label { Text(verbatim: NativeLocalization.string(title)) } icon: { Image(systemName: systemImage) }
                    .font(.headline)
                Spacer()
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
        case .privacy: return NativeLocalization.string("Privacy")
        case .terms: return NativeLocalization.string("Terms")
        case .support: return NativeLocalization.string("Support")
        }
    }
}

private struct LegalCard: View {
    let title: BTCopy
    let messages: [BTCopy]

    var body: some View {
        BTCard {
            BTSectionHeader(title: title)
            ForEach(messages, id: \.self) { message in
                Text(verbatim: message.resolved)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
