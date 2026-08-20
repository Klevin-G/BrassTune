import AuthenticationServices
import SwiftUI
import SafariServices
import UIKit

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

                if !model.authState.usesRemoteAccount {
                    if accountActionsEnabled {
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
                    }

                    if model.appleSignInAvailable {
                        NativeAppleSignInButton(identifier: "settings.appleSignIn")
                    }
                    if model.googleSignInAvailable {
                        NativeGoogleSignInButton(identifier: "settings.googleSignIn")
                    }

                    if model.authProviderConfigurationLoading {
                        ProgressView("Checking sign-in providers…")
                            .accessibilityIdentifier("settings.authProvidersLoading")
                    }
                    if let recovery = model.authProviderRecoveryMessage {
                        Text(verbatim: recovery)
                            .font(.footnote)
                            .foregroundStyle(BTTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.accountConfigurationUnavailable")
                        if accountActionsEnabled {
                            Button("Retry provider check") {
                                Task { await model.loadAuthProviderConfiguration(force: true) }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("settings.authProvidersRetry")
                        }
                    }
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
                .accessibilityValue(Text(verbatim: NativeLocalization.string(advancedTunerExpanded ? "Expanded" : "Collapsed")))
                .accessibilityHint(Text(verbatim: NativeLocalization.string("Advanced tuner settings")))
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
                BTSectionHeader(title: "Your data", subtitle: "Export a copy or clear practice history while keeping imported scores.")
                ShareLink(item: model.exportDataText()) {
                    Label("Export local data", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.exportData")

                Button(role: .destructive) {
                    pendingDestructiveAction = .clearPracticeData
                } label: {
                    Label("Clear practice history", systemImage: "trash")
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
        .task {
            await model.loadAuthProviderConfiguration()
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
            return NativeLocalization.string("Deleting your account removes its server record and clears the saved sign-in, practice history, and imported sheet music on this device.")
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
            return NativeLocalization.string("Practice history, saved recordings, and reflections stored on this device will be deleted. Imported sheet music and your account stay available. This can't be undone.")
        case .deleteAccount:
            if model.authState.usesRemoteAccount {
                return NativeLocalization.string("Your server account record will be deleted, and this device will clear its saved sign-in, practice history, and imported sheet music. This can't be undone.")
            }
            return NativeLocalization.string("Practice history, imported sheet music, and saved sign-in information will be deleted from this device. This can't be undone.")
        }
    }

    private func destructiveButtonTitle(for action: DestructiveAction) -> String {
        switch action {
        case .clearPracticeData:
            return NativeLocalization.string("Delete practice history")
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
        .disabled(model.authOperationInProgress || !model.appleSignInAvailable)
        .accessibilityIdentifier(identifier)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken else {
                model.reportAuthFailure(.authenticationFailed)
                return
            }
            Task { await model.completeAppleSignIn(identityToken: identityToken, rawNonce: rawAppleNonce) }
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            } else {
                model.reportAuthFailure(.authenticationFailed)
            }
        }
    }
}

enum NativeGoogleSignInBranding {
    static let fontName = "GoogleSans-Medium"
    static let fontSize: CGFloat = 14
    static let lineHeight: CGFloat = 20
    static let logoSize: CGFloat = 18
    static let leadingPadding: CGFloat = 16
    static let logoTextSpacing: CGFloat = 12
    static let trailingPadding: CGFloat = 16

    static var lineSpacing: CGFloat {
        guard let font = UIFont(name: fontName, size: fontSize) else { return 0 }
        return max(0, lineHeight - font.lineHeight)
    }
}

struct NativeGoogleSignInButton: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let identifier: String

    var body: some View {
        Button {
            Task { await model.completeGoogleSignIn() }
        } label: {
            HStack(spacing: NativeGoogleSignInBranding.logoTextSpacing) {
                // Exact 18-point standard-color G crop from Google's official
                // pre-approved iOS "Show text=No" artwork.
                Image("GoogleSignInIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: NativeGoogleSignInBranding.logoSize,
                        height: NativeGoogleSignInBranding.logoSize
                    )
                    .accessibilityHidden(true)

                Text("Sign in with Google")
                    .font(.custom(
                        NativeGoogleSignInBranding.fontName,
                        size: NativeGoogleSignInBranding.fontSize,
                        relativeTo: .body
                    ))
                    .lineSpacing(NativeGoogleSignInBranding.lineSpacing)
                    .foregroundStyle(googleTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: NativeGoogleSignInBranding.lineHeight)
            }
            .padding(.leading, NativeGoogleSignInBranding.leadingPadding)
            .padding(.trailing, NativeGoogleSignInBranding.trailingPadding)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(googleBackgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(googleBorderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(model.authOperationInProgress || !model.googleSignInAvailable)
        .opacity(model.authOperationInProgress || !model.googleSignInAvailable ? 0.45 : 1)
        .accessibilityLabel(Text(verbatim: NativeLocalization.string("Sign in with Google")))
        .accessibilityIdentifier(identifier)
    }

    private var googleBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 19.0 / 255.0, green: 19.0 / 255.0, blue: 20.0 / 255.0)
            : .white
    }

    private var googleTextColor: Color {
        colorScheme == .dark
            ? Color(red: 227.0 / 255.0, green: 227.0 / 255.0, blue: 227.0 / 255.0)
            : Color(red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0)
    }

    private var googleBorderColor: Color {
        colorScheme == .dark
            ? Color(red: 142.0 / 255.0, green: 145.0 / 255.0, blue: 143.0 / 255.0)
            : Color(red: 116.0 / 255.0, green: 119.0 / 255.0, blue: 117.0 / 255.0)
    }
}

struct ClassesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var joinCode = ""
    @State private var newClassName = ""
    @State private var inviteUsername = ""
    @State private var inviteInstrumentID = ""
    @State private var invitationInstruments: [EnsembleInvitation.ID: String] = [:]
    @State private var createExpanded = false
    @State private var pendingLeave: EnsembleSummary?
    @State private var pendingMemberRemoval: EnsembleMember?
    @State private var pendingCodeRotation = false
    @State private var authMode: GatewayAuthMode?

    var body: some View {
        BTScreen {
            BTPageHeader(
                eyebrow: "Classes",
                title: "Your classes",
                subtitle: "Join more than one class, switch between them, or leave a class without changing your practice setup."
            )

            if model.testFixturesEnabled || model.authState.usesRemoteAccount {
                invitationContent
                joinCard
                createClassCard
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
                }
            }

            if let message = model.ensembleStatusMessage {
                BTCard(tint: BTTheme.surfaceWarm) {
                    Label { Text(verbatim: message) } icon: { Image(systemName: "checkmark.circle.fill") }
                        .foregroundStyle(BTTheme.success)
                }
                .accessibilityElement(children: .combine)
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
            await model.loadClassWorkspace()
        }
        .task(id: model.selectedEnsembleID) {
            guard let selectedEnsembleID = model.selectedEnsembleID else { return }
            await model.loadSelectedEnsembleDetails(id: selectedEnsembleID)
        }
        .refreshable {
            guard model.testFixturesEnabled || model.authState.usesRemoteAccount else { return }
            await model.loadClassWorkspace()
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
        .confirmationDialog(
            "Remove this class member?",
            isPresented: Binding(
                get: { pendingMemberRemoval != nil },
                set: { if !$0 { pendingMemberRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingMemberRemoval, let groupID = model.selectedEnsembleID {
                Button("Remove member", role: .destructive) {
                    Task {
                        _ = await model.removeEnsembleMember(
                            groupID: groupID,
                            memberID: pendingMemberRemoval.id
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will lose access to this class. Their recordings and reflections stay private in their own account.")
        }
        .confirmationDialog(
            "Replace the class code?",
            isPresented: $pendingCodeRotation,
            titleVisibility: .visible
        ) {
            if let groupID = model.selectedEnsembleID {
                Button("Replace code", role: .destructive) {
                    Task { _ = await model.rotateEnsembleJoinCode(id: groupID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current code will stop working immediately. Existing members keep access.")
        }
        .onChange(of: model.ensembleStatusMessage) { _, message in
            guard UIAccessibility.isVoiceOverRunning, let message else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    @ViewBuilder
    private var invitationContent: some View {
        if !model.ensembleInvitations.isEmpty {
            VStack(alignment: .leading, spacing: BTSpacing.md) {
                BTSectionHeader(
                    title: "Class invitations",
                    subtitle: "You choose whether to join. Pick your own instrument before accepting."
                )
                Text(verbatim: NativeLocalization.string(
                    "Only class-level and student aggregate practice minutes, session counts, and tuning summaries are shared."
                ))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: NativeLocalization.string(
                    "Recordings, live microphone audio, imported sheet music, and private reflections are never shown here."
                ))
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("classes.invitationPrivacy")
                ForEach(model.ensembleInvitations) { invitation in
                    BTCard(tint: BTTheme.surfaceWarm) {
                        Text(verbatim: invitation.groupName)
                            .font(.headline)
                        if let directorName = invitation.directorName {
                            Text(verbatim: NativeLocalization.format("Invited by %@", directorName))
                                .font(.subheadline)
                                .foregroundStyle(BTTheme.muted)
                        }
                        Picker(
                            "Your instrument",
                            selection: Binding(
                                get: {
                                    invitationInstruments[invitation.id]
                                        ?? (invitation.instrumentID == "unassigned"
                                            ? model.selectedInstrumentId
                                            : invitation.instrumentID)
                                },
                                set: { invitationInstruments[invitation.id] = $0 }
                            )
                        ) {
                            instrumentPickerOptions()
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("classes.invitationInstrument.\(invitation.id)")

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: BTSpacing.sm) {
                                invitationDecisionButton(invitation, accept: true)
                                invitationDecisionButton(invitation, accept: false)
                            }
                            VStack(spacing: BTSpacing.sm) {
                                invitationDecisionButton(invitation, accept: true)
                                invitationDecisionButton(invitation, accept: false)
                            }
                        }
                    }
                    .accessibilityIdentifier("classes.invitation.\(invitation.id)")
                }
            }
        }
    }

    private func invitationDecisionButton(
        _ invitation: EnsembleInvitation,
        accept: Bool
    ) -> some View {
        Button(role: accept ? nil : .destructive) {
            Task {
                let chosen = invitationInstruments[invitation.id]
                    ?? (invitation.instrumentID == "unassigned"
                        ? model.selectedInstrumentId
                        : invitation.instrumentID)
                _ = await model.respondToEnsembleInvitation(
                    memberID: invitation.id,
                    accept: accept,
                    instrumentID: accept ? chosen : nil
                )
            }
        } label: {
            Text(verbatim: NativeLocalization.string(
                accept ? "Accept invitation" : "Decline invitation"
            ))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(accept ? BTTheme.accent : BTTheme.danger)
        .disabled(model.ensembleMutationInProgress)
        .accessibilityIdentifier(
            "classes.invitation.\(accept ? "accept" : "decline").\(invitation.id)"
        )
    }

    private var joinCard: some View {
        BTCard {
            BTSectionHeader(title: "Join another class", subtitle: "Enter the code your teacher shared.")
            Text(verbatim: NativeLocalization.string(
                "Only class-level and student aggregate practice minutes, session counts, and tuning summaries are shared."
            ))
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: NativeLocalization.string(
                "Recordings, live microphone audio, imported sheet music, and private reflections are never shown here."
            ))
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("classes.joinPrivacy")
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

    private var createClassCard: some View {
        BTCard {
            Button {
                createExpanded.toggle()
            } label: {
                HStack(spacing: BTSpacing.sm) {
                    Text("Create a class")
                        .font(.headline)
                    Spacer()
                    Image(systemName: createExpanded ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .btMinimumInteractiveSize()
            .accessibilityValue(Text(verbatim: NativeLocalization.string(createExpanded ? "Expanded" : "Collapsed")))
            .accessibilityHint(Text(verbatim: NativeLocalization.string("Create a class")))
            .accessibilityIdentifier("classes.createDisclosure")

            if createExpanded {
                TextField("Class name", text: $newClassName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("classes.createName")
                Button {
                    Task {
                        if await model.createEnsemble(name: newClassName) {
                            newClassName = ""
                            createExpanded = false
                        }
                    }
                } label: {
                    Text(verbatim: NativeLocalization.string(
                        model.ensembleMutationInProgress ? "Creating…" : "Create a class"
                    ))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .disabled(
                    model.ensembleMutationInProgress
                        || newClassName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                )
                .accessibilityIdentifier("classes.create")
            }
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

            if let selected = model.ensembles.first(where: { $0.id == model.selectedEnsembleID }) {
                selectedClassCard(selected)
                if selected.viewerCanManage {
                    directorTools(for: selected)
                } else {
                    memberRoster
                }
            }
        }
    }

    private func selectedClassCard(_ ensemble: EnsembleSummary) -> some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            HStack(alignment: .top, spacing: BTSpacing.md) {
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    Text(verbatim: ensemble.name)
                        .font(.headline)
                    Text(verbatim: ensemble.viewerRoleLabel)
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                }
                Spacer()
                BTStatusPill(text: "Selected", tint: BTTheme.success)
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
            }
        }
    }

    private func directorTools(for ensemble: EnsembleSummary) -> some View {
        VStack(alignment: .leading, spacing: BTSpacing.lg) {
            BTCard {
                BTSectionHeader(
                    title: "Invite students",
                    subtitle: "Share the code or send a private invitation to an existing username."
                )
                if let code = model.selectedEnsembleDetail?.joinCode ?? ensemble.joinCode {
                    Text(verbatim: NativeLocalization.preserve(code))
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                        .accessibilityLabel(NativeLocalization.format("Class code %@", code))
                        .accessibilityIdentifier("classes.director.code")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: BTSpacing.sm) {
                            shareCodeButton(ensemble: ensemble, code: code)
                            rotateCodeButton
                        }
                        VStack(spacing: BTSpacing.sm) {
                            shareCodeButton(ensemble: ensemble, code: code)
                            rotateCodeButton
                        }
                    }
                }

                Picker("Student instrument (optional)", selection: $inviteInstrumentID) {
                    Text("Student chooses").tag("")
                    instrumentPickerOptions()
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("classes.director.inviteInstrument")
                TextField("Student username", text: $inviteUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("classes.director.username")
                Button {
                    Task {
                        if await model.inviteEnsembleMember(
                            groupID: ensemble.id,
                            username: inviteUsername,
                            instrumentID: inviteInstrumentID.isEmpty ? nil : inviteInstrumentID
                        ) {
                            inviteUsername = ""
                            inviteInstrumentID = ""
                        }
                    }
                } label: {
                    Text(verbatim: NativeLocalization.string(
                        model.ensembleMutationInProgress ? "Sending…" : "Send invitation"
                    ))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .disabled(
                    model.ensembleMutationInProgress
                        || inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
                )
                .accessibilityIdentifier("classes.director.invite")
            }

            BTCard(tint: BTTheme.surfaceWarm) {
                BTSectionHeader(
                    title: "What the director can see",
                    subtitle: "Only class-level and student aggregate practice minutes, session counts, and tuning summaries are shared."
                )
                Text("Recordings, live microphone audio, imported sheet music, and private reflections are never shown here.")
                    .font(.footnote)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("classes.director.privacy")

            directorRoster
            directorSummary
        }
    }

    private func shareCodeButton(ensemble: EnsembleSummary, code: String) -> some View {
        ShareLink(
            item: NativeLocalization.format(
                "Join %@ with class code %@.",
                ensemble.name,
                code
            )
        ) {
            Label("Share class code", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .accessibilityIdentifier("classes.director.share")
    }

    private var rotateCodeButton: some View {
        Button {
            pendingCodeRotation = true
        } label: {
            Label("Replace class code", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .disabled(model.ensembleMutationInProgress)
        .accessibilityIdentifier("classes.director.rotate")
    }

    @ViewBuilder
    private var directorRoster: some View {
        BTCard {
            BTSectionHeader(title: "Student roster", subtitle: "Membership and aggregate practice activity.")
            if model.ensemblesLoading && model.selectedEnsembleRoster.isEmpty {
                ProgressView("Loading roster…")
            } else if model.selectedEnsembleRoster.isEmpty {
                Text("No students yet.")
                    .foregroundStyle(BTTheme.muted)
            } else {
                ForEach(model.selectedEnsembleRoster) { student in
                    VStack(alignment: .leading, spacing: BTSpacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: student.displayLabel)
                                .font(.headline)
                            Spacer()
                            if student.status == "invited" {
                                BTStatusPill(text: "Invited", tint: BTTheme.warning)
                            }
                        }
                        Text(verbatim: instrumentDisplayName(student.instrumentID))
                            .font(.subheadline)
                            .foregroundStyle(BTTheme.muted)
                        if student.status == "active" {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: BTSpacing.sm) {
                                    rosterMetrics(student)
                                }
                                VStack(spacing: BTSpacing.sm) {
                                    rosterMetrics(student)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            if let member = model.selectedEnsembleDetail?.members?.first(where: { $0.id == student.memberID }) {
                                pendingMemberRemoval = member
                            }
                        } label: {
                            Text("Remove member")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.ensembleMutationInProgress)
                        .accessibilityIdentifier("classes.director.remove.\(student.memberID)")
                    }
                    .padding(.vertical, BTSpacing.sm)
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .accessibilityIdentifier("classes.director.roster")
    }

    @ViewBuilder
    private func rosterMetrics(_ student: EnsembleRosterStudent) -> some View {
        BTMetricTile(
            title: "Practice time",
            value: .verbatim(NativeLocalization.format("%@ minutes", formatClassNumber(student.practiceMinutes))),
            detail: "aggregate"
        )
        BTMetricTile(
            title: "Sessions",
            value: .verbatim(NativeLocalization.isolate(String(student.sessionsCount))),
            detail: "aggregate",
            tint: BTTheme.secondaryAccent
        )
        if let averageAbsCents = student.averageAbsCents {
            BTMetricTile(
                title: "Average distance",
                value: .verbatim(NativeLocalization.format(
                    "%@ cents",
                    formatClassNumber(averageAbsCents)
                )),
                detail: "aggregate"
            )
            .accessibilityIdentifier("classes.director.averageDistance.\(student.memberID)")
        }
        if let inTunePercentage = student.inTunePercentage {
            BTMetricTile(
                title: "In tune",
                value: .verbatim(NativeLocalization.format(
                    "%@%% in tune",
                    formatClassNumber(inTunePercentage)
                )),
                detail: "aggregate",
                tint: BTTheme.success
            )
            .accessibilityIdentifier("classes.director.inTune.\(student.memberID)")
        }
    }

    @ViewBuilder
    private var directorSummary: some View {
        if let aggregate = model.selectedEnsembleAggregate {
            BTCard {
                BTSectionHeader(
                    title: "Roster summary",
                    subtitle: "Aggregate activity since each student joined."
                )
                .accessibilityIdentifier("classes.director.summary")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BTSpacing.sm) {
                        aggregateMetrics(aggregate)
                    }
                    VStack(spacing: BTSpacing.sm) {
                        aggregateMetrics(aggregate)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func aggregateMetrics(_ aggregate: EnsembleAggregateSummary) -> some View {
        BTMetricTile(
            title: "Practice time",
            value: .verbatim(NativeLocalization.format(
                "%@ minutes",
                formatClassNumber(aggregate.overall.practiceMinutes)
            )),
            detail: "all students"
        )
        BTMetricTile(
            title: "Sessions",
            value: .verbatim(NativeLocalization.isolate(String(aggregate.sessionCount))),
            detail: "all students",
            tint: BTTheme.secondaryAccent
        )
        BTMetricTile(
            title: "Average distance",
            value: .verbatim(NativeLocalization.format(
                "%@ cents",
                formatClassNumber(aggregate.overall.averageAbsCents)
            )),
            detail: "all students"
        )
        .accessibilityIdentifier("classes.director.averageDistance.overall")
    }

    @ViewBuilder
    private var memberRoster: some View {
        if let members = model.selectedEnsembleDetail?.members, !members.isEmpty {
            BTCard {
                BTSectionHeader(title: "Membership", subtitle: "Only the roster details permitted for your role are shown.")
                ForEach(members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: BTSpacing.xs) {
                            Text(verbatim: member.displayLabel)
                                .font(.headline)
                            Text(verbatim: instrumentDisplayName(member.instrumentID))
                                .font(.subheadline)
                                .foregroundStyle(BTTheme.muted)
                        }
                        Spacer()
                        Text(verbatim: NativeLocalization.string(
                            member.status == "invited" ? "Invited" : "Active"
                        ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BTTheme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("classes.membership")
        }
    }

    private func formatClassNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return NativeLocalization.isolate(String(Int(value)))
        }
        return NativeLocalization.isolate(String(format: "%.1f", value))
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
                    .accessibilityHidden(true)
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
    @State private var safariURL: URL?

    var body: some View {
        BTScreen {
            LegalCard(document: document, openURL: { safariURL = $0 })
        }
        .navigationTitle(title)
        .accessibilityIdentifier("screen.legal.\(title)")
        .sheet(isPresented: Binding(
            get: { safariURL != nil },
            set: { if !$0 { safariURL = nil } }
        )) {
            if let safariURL { SafariDocumentView(url: safariURL) }
        }
    }

    private var title: String {
        switch kind {
        case .privacy: return NativeLocalization.string("Privacy")
        case .terms: return NativeLocalization.string("Terms")
        case .support: return NativeLocalization.string("Support")
        }
    }

    private var document: LegalDocument {
        switch kind {
        case .privacy:
            return LegalDocument(
                title: "Privacy Policy",
                url: URL(string: "https://brasstune.vercel.app/privacy")!,
                sections: [
                    ("Data BrassTune uses", ["BrassTune uses your profile, settings, practice sessions, pitch results, reflections, and recordings to provide practice features. Supabase provides account authentication and storage for signed-in cloud practice; Vercel hosts the web app and Render hosts the backend service.", "Native microphone audio and imported score pages stay on this device unless you explicitly export or share them. Signed-in web recording behavior is described on the published policy page."]),
                    ("Class privacy", ["Class directors can see aggregate cloud practice totals from the date you join through class reports. They never receive your recordings, reflection text, or private session details. A limited set of authorized BrassTune service administrators may access account, session, and cloud-audio data only for security, support, abuse investigation, or service operation."]),
                    ("Your control", ["You can export or delete saved data from Settings. Account access and local data are removed when deletion succeeds. If cloud-file cleanup is queued, BrassTune reports that pending state and continues the protected cleanup job instead of claiming every stored object is already gone. Exported copies are yours to manage."])
                ]
            )
        case .terms:
            return LegalDocument(
                title: "Terms of Service",
                url: URL(string: "https://brasstune.vercel.app/terms")!,
                sections: [
                    ("Using BrassTune", ["Use BrassTune with permission from the account holder, and follow your school or studio’s rules.", "BrassTune gives you practice feedback and tuning help. It does not replace a teacher, medical advice, or hearing-safety guidance.", "You choose when to record. Check exports before sharing them and follow your class or school rules for student data."]),
                    ("Accounts and data", ["You can export your data and delete your account from Settings. When a teacher deletes their account, their classes are deleted too."])
                ]
            )
        case .support:
            return LegalDocument(
                title: "Support",
                url: URL(string: "https://brasstune.vercel.app/support")!,
                sections: [
                    ("Need help?", ["Students: your teacher or director can usually help fastest. For anything else, email us and tell us which screen you were on and roughly when it happened.", "Support contact: brasstune1@gmail.com"]),
                    ("Common next steps", ["If the tuner stays quiet, check microphone access in Settings. You can export a session or delete your account from Settings."])
                ]
            )
        }
    }
}

private struct LegalDocument {
    let title: String
    let url: URL
    let sections: [(String, [String])]
}

private struct LegalCard: View {
    let document: LegalDocument
    let openURL: (URL) -> Void

    var body: some View {
        BTCard {
            BTSectionHeader(title: .verbatim(document.title), subtitle: "Published at the link below")
            ForEach(document.sections, id: \.0) { section in
                Text(verbatim: section.0).font(.headline)
                ForEach(section.1, id: \.self) { message in
                    Text(verbatim: message).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(verbatim: document.url.absoluteString).font(.footnote.monospaced()).foregroundStyle(BTTheme.muted).textSelection(.enabled).accessibilityIdentifier("legal.canonicalURL")
            Button { openURL(document.url) } label: {
                Label("Open published document", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("legal.openPublished")
        }
    }
}

private struct SafariDocumentView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
