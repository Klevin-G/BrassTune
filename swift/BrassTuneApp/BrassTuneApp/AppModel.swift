import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig = .fromProcessEnvironment()
    @Published var authState: AuthState = .guest
    @Published var selectedInstrumentId = "trumpet"
    @Published var referencePitchHz = 440.0
    @Published var sessions: [PracticeSession] = []
    @Published var ensembles: [EnsembleSummary] = AppModel.demoEnsembles
    @Published var lastError: UserVisibleError?

    let audioEngine = NativeAudioEngine()
    let apiClient = APIClient()
    let authService = AuthService()

    static let demoEnsembles = [
        EnsembleSummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Demo brass studio",
            role: "Demo student",
            activeMembers: 4,
            focus: "Center D5 before range expansion."
        )
    ]

    var analyticsSnapshot: AnalyticsSnapshot {
        AnalyticsSnapshot(sessions: sessions)
    }

    var accountFeaturesEnabled: Bool {
        config.supabaseURL != nil && !(config.supabasePublishableKey ?? "").isEmpty
    }

    var accountUnavailableMessage: String? {
        accountFeaturesEnabled ? nil : "Accounts are not enabled in this beta build yet. Guest practice still works on this device."
    }

    func resetForUITesting() {
        authService.deleteStoredAuth()
        authState = .guest
        selectedInstrumentId = "trumpet"
        referencePitchHz = 440.0
        sessions.removeAll()
        ensembles = Self.demoEnsembles
        lastError = nil
    }

    func enterGuestDemo() {
        authState = .guest
        if ensembles.isEmpty {
            ensembles = Self.demoEnsembles
        }
        lastError = nil
    }

    func signOut() {
        authService.signOut()
        authState = .signedOut
        ensembles.removeAll()
        lastError = nil
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

    func deleteSession(id: PracticeSession.ID) {
        sessions.removeAll { $0.id == id }
    }

    func exportDataText() -> String {
        var lines = [
            "BrassTune local data export",
            "Account state: \(authState.displayTitle)",
            "Environment: \(config.environment.rawValue)",
            "Instrument: \(selectedInstrumentId)",
            "Reference pitch: \(String(format: "%.1f", referencePitchHz)) Hz",
            "Sessions: \(sessions.count)",
            "Account features: \(accountFeaturesEnabled ? "configured" : "disabled")",
        ]
        let analytics = analyticsSnapshot
        if analytics.hasSessions {
            lines.append("Average absolute cents: \(String(format: "%.1f", analytics.averageAbsCents))")
            lines.append("Average in-tune percentage: \(String(format: "%.0f", analytics.averageInTunePercentage))%")
            lines.append("")
            lines.append("Sessions")
            lines.append(contentsOf: sessions.map(\.exportText))
        } else {
            lines.append("No local practice sessions have been recorded.")
        }
        return lines.joined(separator: "\n")
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
        lastError = nil
    }

    func startDemoRecording() {
        audioEngine.startFixtureRecording(instrumentId: selectedInstrumentId, referencePitchHz: referencePitchHz)
    }

    func stopDemoRecording() {
        let frames = audioEngine.stopFixtureRecording()
        let endedAt = Date()
        let startedAt = endedAt.addingTimeInterval(-Double(frames.count) * 0.11)
        let demoIndex = sessions.count + 1
        let session = PracticeSession(
            id: UUID(),
            name: demoIndex == 1 ? "Guided take" : "Guided take \(demoIndex)",
            instrumentId: selectedInstrumentId,
            startedAt: startedAt,
            endedAt: endedAt,
            frames: frames,
            retainedRecordingURL: nil
        )
        sessions.insert(session, at: 0)
    }
}

private struct BackendDeletionResponse: Decodable {
    let deleted: Bool
}
