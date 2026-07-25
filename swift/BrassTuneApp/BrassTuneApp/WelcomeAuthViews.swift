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
    @AccessibilityFocusState private var gatewayErrorFocused: Bool
    @State private var focusedGatewayError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BTSpacing.xl) {
                    Spacer(minLength: BTSpacing.lg)
                    GatewayWelcomeHeader()
                    if horizontalSizeClass == .regular {
                        GatewayPracticePreview()
                    }

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

                    Text("Guest practice remains on this device. Create an account to back up progress and join Classes.")
                        .font(.footnote)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BTSpacing.xl)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GatewayActions(authPresentation: $authPresentation)
            }
            .background(BTTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .accessibilityIdentifier("screen.gateway")
        .sheet(item: $authPresentation) { presentation in
            GatewayAuthForm(mode: presentation.mode, context: presentation.context)
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
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            Image(systemName: "tuningfork")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(BTTheme.accent)
                .accessibilityHidden(true)
            Text("Welcome to BrassTune")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("Play your first note in under a minute. Tune accurately, start a guided warm-up, and track progress.")
                .font(.body)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct GatewayPracticePreview: View {
    var body: some View {
        HStack(alignment: .top, spacing: BTSpacing.md) {
            previewCard(
                title: "Find the center",
                detail: "Play a note and BrassTune will show whether it is flat, in tune, or sharp."
            )
            previewCard(
                title: "Guided five-minute warm-up",
                detail: "Five short steps for steady air, relaxed attacks, and centered notes."
            )
            previewCard(
                title: "Practice momentum",
                detail: "See what you did today, how this week is going, and what to try next."
            )
        }
        .accessibilityIdentifier("gateway.practicePreview")
    }

    private func previewCard(title: BTCopy, detail: BTCopy) -> some View {
        VStack(alignment: .leading, spacing: BTSpacing.sm) {
            Text(verbatim: title.resolved)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: detail.resolved)
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BTSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .btContentSurface(tint: BTTheme.surface)
    }
}

private struct GatewayActions: View {
    @EnvironmentObject private var model: AppModel
    @Binding var authPresentation: GatewayAuthPresentation?

    var body: some View {
        VStack(spacing: BTSpacing.sm) {
            Button(action: startAsGuest) {
                Label("Start as guest", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BTPrimaryButtonStyle())
            .accessibilityHint("Starts local practice without an online account")
            .accessibilityIdentifier("gateway.continueAsGuest")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: BTSpacing.sm) {
                    accountButton(mode: .createAccount)
                    accountButton(mode: .signIn)
                }
                VStack(spacing: BTSpacing.sm) {
                    accountButton(mode: .createAccount)
                    accountButton(mode: .signIn)
                }
            }

            if !model.accountFeaturesEnabled {
                Label {
                    Text(verbatim: model.accountUnavailableMessage ?? NativeLocalization.string("Practice as a guest today. Online backup and Classes will appear when account access is available."))
                } icon: {
                    Image(systemName: "icloud.slash")
                }
                .font(.footnote)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gateway.accountConfigurationUnavailable")
            }

            Button(action: openClassSignIn) {
                Label("I have a class code", systemImage: "number.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .btMinimumInteractiveSize()
            .accessibilityIdentifier("gateway.classCode")
        }
        .padding(.horizontal, BTSpacing.lg)
        .padding(.top, BTSpacing.sm)
        .padding(.bottom, BTSpacing.lg)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background(.bar)
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

    init(mode: GatewayAuthMode, context: GatewayAuthContext = .standard) {
        self.context = context
        _activeMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
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

                if model.accountFeaturesEnabled {
                    emailAccountForm
                } else {
                    Section {
                        Label {
                            Text(verbatim: model.accountUnavailableMessage ?? NativeLocalization.string("Practice as a guest today. Online backup and Classes will appear when account access is available."))
                        } icon: {
                            Image(systemName: "icloud.slash")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateway.authUnavailable")
                    } header: {
                        Text("Practice is ready")
                    } footer: {
                        Text("You can start as guest and add account backup later.")
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
        .presentationDetents([.large])
        .task {
            await model.loadAuthProviderConfiguration()
        }
    }

    @ViewBuilder
    private var providerSignInSection: some View {
        if model.appleSignInAvailable || model.authProviderConfigurationLoading || model.authProviderRecoveryMessage != nil {
            Section {
                if model.appleSignInAvailable {
                    NativeAppleSignInButton(identifier: "gateway.authAppleSignIn")
                    if model.googleSignInAvailable {
                        NativeGoogleSignInButton(identifier: "gateway.authGoogleSignIn")
                    }
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
                .accessibilityIdentifier("gateway.email")
            SecureField("Password", text: $password)
                .textContentType(activeMode == .signIn ? .password : .newPassword)
                .accessibilityIdentifier("gateway.password")
        } header: {
            Text("Email")
        } footer: {
            Text("Your sign-in is stored securely in Keychain on this device.")
        }

        if let notice = model.authNotice {
            Section {
                Label {
                    Text(verbatim: notice)
                } icon: {
                    Image(systemName: model.authNoticeIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                }
                .foregroundStyle(model.authNoticeIsError ? BTTheme.danger : BTTheme.success)
                .fixedSize(horizontal: false, vertical: true)
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
                    model.authOperationInProgress
                        || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("gateway.passwordReset")
            }
        }

        Section {
            Button {
                activeMode = activeMode == .signIn ? .createAccount : .signIn
                model.clearAuthNotice()
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
                || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || password.isEmpty
        )
        .accessibilityIdentifier("gateway.submitAuth")
    }

    private func submit() {
        Task {
            switch activeMode {
            case .signIn:
                await model.signIn(email: email, password: password)
            case .createAccount:
                await model.signUp(email: email, password: password)
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
}
