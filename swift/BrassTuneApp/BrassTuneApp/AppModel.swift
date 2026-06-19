import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig = .fromProcessEnvironment()
    @Published var authState: AuthState = .guest
    @Published var selectedInstrumentId = "trumpet"
    @Published var referencePitchHz = 440.0
    @Published var sessions: [PracticeSession] = []
    @Published var ensembles: [EnsembleSummary] = [
        EnsembleSummary(id: UUID(), name: "Central Wind Ensemble Brass", role: "student", activeMembers: 4, focus: "Center D5 before range expansion.")
    ]
    @Published var lastError: UserVisibleError?

    let audioEngine = NativeAudioEngine()
    let apiClient = APIClient()
    let authService = AuthService()

    func resetForUITesting() {
        authService.deleteStoredAuth()
        authState = .guest
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440.0
        sessions.removeAll()
        ensembles = [
            EnsembleSummary(id: UUID(), name: "Central Wind Ensemble Brass", role: "student", activeMembers: 4, focus: "Center D5 before range expansion.")
        ]
        lastError = nil
    }

    func enterGuestDemo() {
        authState = .guest
    }

    func signOut() {
        authService.signOut()
        authState = .signedOut
    }

    func restoreSession() async {
        do {
            if let session = try await authService.refreshStoredSession(config: config) {
                authState = .signedIn(email: session.email)
            }
        } catch {
            if let session = authService.restoreSession() {
                authState = .signedIn(email: session.email)
            }
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await authService.signIn(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func signUp(email: String, password: String) async {
        do {
            let session = try await authService.signUp(email: email, password: password, config: config)
            authState = .signedIn(email: session.email)
        } catch UserVisibleError.authenticationFailed {
            authState = .emailConfirmationRequired(email: email)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func requestPasswordReset(email: String) async {
        do {
            try await authService.requestPasswordReset(email: email, config: config)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func completeAppleSignIn(identityToken: Data, rawNonce: String) async {
        do {
            let session = try await authService.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, config: config)
            authState = .signedIn(email: session.email)
        } catch {
            lastError = (error as? UserVisibleError) ?? .authenticationFailed
        }
    }

    func deleteAccount(confirmation: String) async {
        guard confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete my account" else {
            lastError = .accountDeletionRequiresConfirmation
            return
        }
        if let token = authService.accessToken() {
            do {
                let body = try JSONSerialization.data(withJSONObject: ["confirmation": "delete my account"])
                _ = try await apiClient.request(
                    BackendDeletionResponse.self,
                    path: "/api/users/me",
                    method: "DELETE",
                    body: body,
                    config: config,
                    bearerToken: token
                )
            } catch {
                lastError = (error as? UserVisibleError) ?? .networkUnavailable
                return
            }
        }
        sessions.removeAll()
        ensembles.removeAll()
        authService.deleteStoredAuth()
        authState = .signedOut
    }

    func startDemoRecording() {
        audioEngine.startFixtureRecording(instrumentId: selectedInstrumentId, referencePitchHz: referencePitchHz)
    }

    func stopDemoRecording() {
        let frames = audioEngine.stopFixtureRecording()
        let session = PracticeSession(
            id: UUID(),
            name: "Demo take",
            instrumentId: selectedInstrumentId,
            startedAt: Date(),
            endedAt: Date(),
            frames: frames,
            retainedRecordingURL: nil
        )
        sessions.insert(session, at: 0)
    }
}

private struct BackendDeletionResponse: Decodable {
    let deleted: Bool
}
