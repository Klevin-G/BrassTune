import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var onboardingPresented: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var deletionConfirmation = ""
    @State private var rawAppleNonce = ""

    var body: some View {
        List {
            Section("Tuner") {
                Picker("Instrument", selection: $model.selectedInstrumentId) {
                    Text("Trumpet in Bb").tag("trumpet")
                    Text("Horn in F").tag("horn")
                    Text("Trombone").tag("trombone")
                    Text("Euphonium").tag("euphonium")
                    Text("Tuba").tag("tuba")
                }
                Stepper("A4 \(model.referencePitchHz, specifier: "%.1f") Hz", value: $model.referencePitchHz, in: 430...450, step: 0.5)
                Button("Reopen onboarding") { onboardingPresented = true }
            }
            Section("Account") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Button("Sign in") {
                    Task { await model.signIn(email: email, password: password) }
                }
                Button("Create account") {
                    Task { await model.signUp(email: email, password: password) }
                }
                Button("Send password reset") {
                    Task { await model.requestPasswordReset(email: email) }
                }
                SignInWithAppleButton(.signIn) { request in
                    rawAppleNonce = AuthService.randomNonce()
                    request.requestedScopes = [.email]
                    request.nonce = AuthService.sha256(rawAppleNonce)
                } onCompletion: { result in
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
                .frame(height: 44)
                .accessibilityIdentifier("settings.appleSignIn")
                Button("Continue as guest") { model.enterGuestDemo() }
                Button("Sign out") { model.signOut() }
            }
            Section("Data") {
                NavigationLink("Privacy Policy") { LegalDetailView(kind: .privacy) }
                NavigationLink("Terms of Service") { LegalDetailView(kind: .terms) }
                NavigationLink("Support") { LegalDetailView(kind: .support) }
                ShareLink("Export data", item: "BrassTune export")
                TextField("Type delete my account", text: $deletionConfirmation)
                Button("Delete account", role: .destructive) {
                    Task { await model.deleteAccount(confirmation: deletionConfirmation) }
                }
                .disabled(deletionConfirmation.lowercased() != "delete my account")
                .accessibilityIdentifier("settings.deleteAccount")
            }
            if let error = model.lastError {
                Section("Status") {
                    Text(error.localizedDescription)
                }
            }
        }
        .navigationTitle("Settings")
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
        List {
            switch kind {
            case .privacy:
                Section("Privacy Policy") {
                    Text("BrassTune uses account, practice, pitch, recommendation, ensemble, export, and optional recording data to provide tuning feedback and account lifecycle controls.")
                    Text("Local media imports are analyzed on device; source video or audio is not uploaded.")
                }
            case .terms:
                Section("Terms of Service") {
                    Text("Use BrassTune only with consent and within the policies of the school, studio, or organization providing access.")
                    Text("BrassTune is practice analytics software and does not replace instruction or hearing-safety guidance.")
                }
            case .support:
                Section("Support") {
                    Text("Contact the teacher, director, or organization that provided BrassTune access. Include the affected screen and approximate time of the issue.")
                }
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch kind {
        case .privacy: return "Privacy"
        case .terms: return "Terms"
        case .support: return "Support"
        }
    }
}
