import SwiftUI
import UIKit

enum GatewayAuthMode: String, Identifiable {
    case signIn
    case createAccount

    var id: String { rawValue }

    var title: String {
        NativeLocalization.string(self == .signIn ? "Sign in" : "Create free account")
    }
}

enum GatewayAuthContext: String {
    case standard
    case classCode
}

private struct GatewayAuthPresentation: Identifiable {
    let mode: GatewayAuthMode
    let context: GatewayAuthContext

    var id: String { "\(mode.rawValue)-\(context.rawValue)" }
}

struct AuthGatewayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var authPresentation: GatewayAuthPresentation?
    @State private var showingCredits = false
    @AccessibilityFocusState private var gatewayErrorFocused: Bool
    @State private var focusedGatewayError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BTSpacing.xl) {
                    GatewayWelcomeHeader()

                    if case .emailConfirmationRequired(let email) = model.authState {
                        BTCard(tint: BTTheme.surfaceWarm) {
                            Label("Check your email to confirm this BrassTune account before signing in.", systemImage: "envelope.badge")
                                .font(.headline)
                            Text(verbatim: AuthState.emailConfirmationRequired(email: email).displayTitle)
                                .foregroundStyle(BTTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("gateway.confirmationRequired")
                    }

                    if model.authNoticeIsError, let notice = model.authNotice {
                        BTCard(tint: BTTheme.surfaceWarm) {
                            Label {
                                Text(verbatim: notice)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .font(.headline)
                            .foregroundStyle(BTTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityFocused($gatewayErrorFocused)
                        .accessibilityIdentifier("gateway.sessionError")
                    }

                    if let persistenceError = model.persistenceErrorMessage {
                        Label {
                            Text(verbatim: persistenceError)
                        } icon: {
                            Image(systemName: "externaldrive.badge.exclamationmark")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BTTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.persistenceError")
                    }

                    GatewayActions(authPresentation: $authPresentation, openCredits: { showingCredits = true })
                    GatewayInstrumentVisual()

                }
                .padding(BTSpacing.xl)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(BTTheme.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("screen.gateway")
        .sheet(item: $authPresentation) { presentation in
            GatewayAuthForm(mode: presentation.mode, context: presentation.context)
        }
        .sheet(isPresented: $showingCredits) {
            NavigationStack {
                LegalDetailView(kind: .credits)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingCredits = false }
                                .accessibilityIdentifier("gateway.creditsDone")
                        }
                    }
            }
        }
        .onAppear { focusGatewayErrorIfNeeded() }
        .onChange(of: model.authNotice) { _, _ in
            focusGatewayErrorIfNeeded()
        }
    }

    private func focusGatewayErrorIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning,
              model.authNoticeIsError,
              let notice = model.authNotice else {
            focusedGatewayError = nil
            return
        }
        guard focusedGatewayError != notice else { return }
        focusedGatewayError = notice
        DispatchQueue.main.async { gatewayErrorFocused = true }
    }
}

private struct GatewayWelcomeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.lg) {
            Text("BrassTune")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BTTheme.accent)

            Text("Pick up your instrument.")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("Tune a note, set a pulse, or choose a passage to work on.")
                .font(.body)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct GatewayInstrumentVisual: View {
    private let assetName = "welcome-brass-instrument"

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: BTSpacing.sm, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GatewayActions: View {
    @EnvironmentObject private var model: AppModel
    @Binding var authPresentation: GatewayAuthPresentation?
    let openCredits: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            if model.accountFeaturesEnabled {
                Text("Create a free account to personalize your BrassTune practice profile.")
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gateway.accountExplanation")

                Button {
                    authPresentation = GatewayAuthPresentation(mode: .createAccount, context: .standard)
                } label: {
                    Label("Create free account", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BTPrimaryButtonStyle())
                .accessibilityHint("Set up a profile for BrassTune account features")
                .accessibilityIdentifier("gateway.createAccount")

                accountButton(mode: .signIn)
                guestButton

                Text("Your guest practice stays on this device.")
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gateway.guestDisclosure")

                Text("BrassTune does not use account sign-in to back up this device's practice data in this release.")
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("gateway.backupDisclosure")
            } else {
                guestButton
            }

            if !model.accountFeaturesEnabled {
                Label {
                    Text(verbatim: model.accountUnavailableMessage ?? NativeLocalization.string("Practice as a guest today. Account sign-in will be available when account access is ready."))
                } icon: {
                    Image(systemName: "icloud.slash")
                }
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gateway.accountConfigurationUnavailable")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BTSpacing.lg) {
                    footerLinks
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: BTSpacing.xs) {
                    footerLinks
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footerLinks: some View {
        if NativeReleaseFeatureFlags.classes && model.accountFeaturesEnabled {
            Text("Sign in before using classes.")
                .font(.caption)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openClassSignIn) {
                Text("I have a class code")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .btMinimumInteractiveSize()
            .accessibilityIdentifier("gateway.classCode")
        }

        Button(action: openCredits) {
            Text("Credits")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .btMinimumInteractiveSize()
        .accessibilityIdentifier("gateway.credits")
    }

    private func accountButton(mode: GatewayAuthMode) -> some View {
        Button {
            authPresentation = GatewayAuthPresentation(mode: mode, context: .standard)
        } label: {
            Label {
                Text(verbatim: mode.title)
            } icon: {
                Image(systemName: mode == .createAccount
                    ? "person.crop.circle.badge.plus"
                    : "person.crop.circle.badge.checkmark")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BTSecondaryButtonStyle())
        .accessibilityIdentifier(mode == .createAccount ? "gateway.createAccount" : "gateway.signIn")
    }

    @ViewBuilder
    private var guestButton: some View {
        if model.accountFeaturesEnabled {
            guestButtonBody
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .btMinimumInteractiveSize()
        } else {
            guestButtonBody.buttonStyle(BTPrimaryButtonStyle())
        }
    }

    private var guestButtonBody: some View {
        Button(action: startAsGuest) {
            Label("Continue as guest", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .accessibilityHint("Starts local practice without an online account")
        .accessibilityIdentifier("gateway.continueAsGuest")
    }

    private func startAsGuest() {
        model.clearPendingDestination()
        model.enterGuestDemo()
    }

    private func openClassSignIn() {
        model.requestClassDestination()
        authPresentation = GatewayAuthPresentation(mode: .signIn, context: .classCode)
    }
}

struct GatewayAuthForm: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let context: GatewayAuthContext
    @State private var activeMode: GatewayAuthMode
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: AuthField?
    @AccessibilityFocusState private var authNoticeFocused: Bool
    @State private var announcedAuthNotice: String?

    private enum AuthField { case email, password }

    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailError: String? {
        guard !normalizedEmail.isEmpty else { return "Enter your email address." }
        return normalizedEmail.contains("@") && normalizedEmail.contains(".") ? nil : "Enter a valid email address."
    }
    private var passwordError: String? {
        guard !password.isEmpty else { return "Enter your password." }
        if activeMode == .createAccount && password.count < 8 { return "Use at least 8 characters for a new password." }
        return nil
    }
    private var formIsValid: Bool { emailError == nil && passwordError == nil }

    init(mode: GatewayAuthMode, context: GatewayAuthContext = .standard) {
        self.context = context
        _activeMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            if let upgrade = model.guestAccountUpgradePrompt {
                GuestAccountUpgradeDecisionView(prompt: upgrade)
            } else {
                accountForm
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.guestAccountUpgradePrompt != nil)
        .task {
            guard model.guestAccountUpgradePrompt == nil else { return }
            model.clearAuthNotice()
            await model.loadAuthProviderConfiguration()
            focusAuthNoticeIfNeeded()
        }
        .onChange(of: model.authNotice) { _, _ in focusAuthNoticeIfNeeded() }
        // A guest upgrade deliberately remains in guest state until its
        // explicit decision. Dismiss only after merge/keep-separate has
        // committed an authenticated namespace; cancellation remains on the
        // gateway with the guest session intact.
        .onChange(of: model.authState) { _, state in
            guard state.usesRemoteAccount,
                  model.guestAccountUpgradePrompt == nil else { return }
            dismiss()
        }
    }

    private var accountForm: some View {
        Form {
            if context == .classCode {
                Section {
                    Label("Sign in, then BrassTune will take you to Class without losing your place.", systemImage: "person.3")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.classIntent")
                }
            }

                providerSignInSection

                Section {
                    NavigationLink {
                        LegalDetailView(kind: .privacy)
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("gateway.privacyLink")

                    NavigationLink {
                        LegalDetailView(kind: .terms)
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("gateway.termsLink")
                } footer: {
                    Text("Review these before creating or signing in to an account.")
                }

                if model.accountFeaturesEnabled {
                    emailAccountForm
                } else {
                    Section {
                        Label {
                            Text(verbatim: model.accountUnavailableMessage ?? NativeLocalization.string("Practice as a guest today. Account sign-in will be available when account access is ready."))
                        } icon: {
                            Image(systemName: "icloud.slash")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.authUnavailable")
                    } header: {
                        Text("Practice is ready")
                    } footer: {
                        Text("You can start as a guest and choose to sign in later.")
                    }
                }

                if let persistenceError = model.persistenceErrorMessage {
                    Section {
                        Label {
                            Text(verbatim: persistenceError)
                        } icon: {
                            Image(systemName: "externaldrive.badge.exclamationmark")
                        }
                        .foregroundStyle(BTTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.authPersistenceError")
                    } header: {
                        Text("Saved data")
                    }
                }

                Section {
                    Button(action: continueAsGuest) {
                        Label("Not now, keep practicing", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("gateway.authGuestEscape")
                }
        }
        .navigationTitle(activeMode.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not now") { dismiss() }
            }
            if model.accountFeaturesEnabled {
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
        }
    }

    @ViewBuilder
    private var providerSignInSection: some View {
        if model.appleSignInAvailable || model.googleSignInAvailable || model.authProviderConfigurationLoading || model.authProviderRecoveryMessage != nil {
            Section {
                if model.appleSignInAvailable {
                    NativeAppleSignInButton(identifier: "gateway.authAppleSignIn")
                }
                if model.googleSignInAvailable {
                    NativeGoogleSignInButton(identifier: "gateway.authGoogleSignIn")
                }
                if model.authProviderConfigurationLoading {
                    ProgressView("Checking sign-in providers…")
                        .accessibilityIdentifier("gateway.authProvidersLoading")
                }
                if let recovery = model.authProviderRecoveryMessage {
                    Text(verbatim: recovery)
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.authProvidersRecovery")
                    if model.accountFeaturesEnabled {
                        Button("Retry provider check") {
                            Task { await model.loadAuthProviderConfiguration(force: true) }
                        }
                        .accessibilityIdentifier("gateway.authProvidersRetry")
                    }
                }
            } header: {
                Text("Other sign-in options")
            }
        }
    }

    @ViewBuilder
    private var emailAccountForm: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .accessibilityIdentifier("gateway.email")
            if let emailError, !normalizedEmail.isEmpty {
                Text(verbatim: emailError).font(.footnote).foregroundStyle(BTTheme.danger).accessibilityIdentifier("gateway.emailError")
            }
            SecureField("Password", text: $password)
                .textContentType(activeMode == .signIn ? .password : .newPassword)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .accessibilityIdentifier("gateway.password")
            if let passwordError, !password.isEmpty {
                Text(verbatim: passwordError)
                    .font(.footnote)
                    .foregroundStyle(BTTheme.danger)
                    .accessibilityIdentifier("gateway.passwordError")
            }
        } header: {
            Text("Email")
        } footer: {
            if activeMode == .createAccount {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use at least 8 characters for a new password.")
                    Text("Your sign-in is stored securely in Keychain on this device.")
                }
            } else {
                Text("Your sign-in is stored securely in Keychain on this device.")
            }
        }

        if model.authOperationInProgress {
            Section { ProgressView("Contacting BrassTune…").accessibilityIdentifier("gateway.authProgress") }
        }

        // Provider sign-in does not use the email/password fields. Its errors
        // must remain visible even when those unrelated fields are empty.
        if let notice = model.authNotice {
            Section {
                Label {
                    Text(verbatim: notice)
                } icon: {
                    Image(systemName: model.authNoticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                }
                .foregroundStyle(model.authNoticeIsError ? BTTheme.danger : BTTheme.success)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityFocused($authNoticeFocused)
                .accessibilityIdentifier("gateway.authNotice")
            }
        }

        if activeMode == .signIn {
            Section {
                Button {
                    Task { await model.requestPasswordReset(email: email) }
                } label: {
                    Label("Send password reset", systemImage: "envelope")
                        .frame(maxWidth: .infinity)
                }
                .disabled(
                    model.authOperationInProgress || emailError != nil
                )
                .accessibilityIdentifier("gateway.passwordReset")
            }
        }

        Section {
            Button {
                activeMode = activeMode == .signIn ? .createAccount : .signIn
                model.clearAuthNotice()
                focusedField = .email
            } label: {
                Text(verbatim: NativeLocalization.string(
                    activeMode == .signIn ? "Create an account instead" : "Sign in instead"
                ))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("gateway.switchAuthMode")
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(verbatim: model.authOperationInProgress ? NativeLocalization.string("Working…") : activeMode.title)
        }
        .disabled(
            model.authOperationInProgress
                || !formIsValid
        )
        .accessibilityIdentifier("gateway.submitAuth")
    }

    private func submit() {
        guard formIsValid else {
            focusedField = emailError == nil ? .password : .email
            return
        }
        model.clearAuthNotice()
        Task {
            switch activeMode {
            case .signIn:
                await model.signIn(email: normalizedEmail, password: password)
            case .createAccount:
                await model.signUp(email: normalizedEmail, password: password)
            }
            if model.authState.usesRemoteAccount {
                dismiss()
            }
        }
    }

    private func continueAsGuest() {
        model.clearPendingDestination()
        model.enterGuestDemo()
        dismiss()
    }

    private func focusAuthNoticeIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning,
              model.authNoticeIsError,
              let notice = model.authNotice,
              announcedAuthNotice != notice else {
            if model.authNotice == nil || !model.authNoticeIsError {
                announcedAuthNotice = nil
            }
            return
        }
        announcedAuthNotice = notice
        DispatchQueue.main.async {
            authNoticeFocused = true
            UIAccessibility.post(notification: .announcement, argument: notice)
        }
    }
}

struct GuestAccountUpgradeDecisionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let prompt: GuestAccountUpgradePrompt

    var body: some View {
        Form {
            Section {
                Label {
                    Text(verbatim: NativeLocalization.format("You signed in as %@.", NativeLocalization.preserve(prompt.email)))
                } icon: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                .fixedSize(horizontal: false, vertical: true)

                if prompt.containsFileBackedData {
                    Text("This guest practice includes saved recordings or imported sheet music. BrassTune will not move those files automatically because a failed move could lose them. Keep the account and guest practice separate, or cancel and stay in guest practice.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.guestUpgradeFileWarning")
                } else {
                    Text("Choose how to handle this device's guest practice before continuing.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                }

                Button("Merge guest practice") {
                    model.resolveGuestAccountUpgrade(.merge)
                }
                .disabled(!prompt.canMerge)
                .accessibilityIdentifier("gateway.guestUpgradeMerge")

                Button("Keep practice separate") {
                    model.resolveGuestAccountUpgrade(.keepSeparate)
                }
                .accessibilityIdentifier("gateway.guestUpgradeSeparate")

                Button("Cancel sign-in", role: .cancel) {
                    model.resolveGuestAccountUpgrade(.cancel)
                    dismiss()
                }
                .accessibilityIdentifier("gateway.guestUpgradeCancel")
            } footer: {
                Text("BrassTune does not use account sign-in to back up this device's practice data in this release.")
            }

            if model.authNoticeIsError, let notice = model.authNotice {
                Section {
                    Label {
                        Text(verbatim: notice)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(BTTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("guestUpgrade.error")
                }
            }
        }
        .tint(BTTheme.accent)
        .navigationTitle("Keep or merge guest practice?")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("guestUpgrade.decision")
    }
}
