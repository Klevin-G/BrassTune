import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class AuthService: NSObject {
    static let productionOAuthCallbackScheme = "com.brasstune.auth"
    static let developmentOAuthCallbackScheme = "com.brasstune.auth.dev"
    static let productionBundleIdentifier = "com.aryasalem.BrassTune"
    static let developmentBundleIdentifiers: Set<String> = [
        "com.aryasalem.BrassTune.dev",
        "com.brasstune.BrassTuneAppTests.dev",
        "com.brasstune.BrassTuneAppUITests.dev",
    ]
    static let oauthCallbackSchemeInfoKey = "BRASSTUNE_AUTH_CALLBACK_SCHEME"
    static let oauthCallbackScheme = resolvedOAuthCallbackScheme(
        rawValue: Bundle.main.object(forInfoDictionaryKey: oauthCallbackSchemeInfoKey) as? String,
        bundleIdentifier: Bundle.main.bundleIdentifier
    )
    static let googleOAuthCallbackHost = "oauth"
    static let googleOAuthCallbackPath = "/google"
    static let passwordResetWebURLString = "https://brasstune.vercel.app/auth/reset-password"

    private let session: URLSession
    private let readSessionPayload: () throws -> String?
    private let saveSessionPayload: (String) throws -> Void
    private let deleteSessionPayload: () throws -> Void
    private let webAuthenticationOverride: ((URL, String) async throws -> URL)?
    private var webAuthenticationSession: ASWebAuthenticationSession?

    init(
        session: URLSession = .shared,
        service: String = "com.brasstune.auth",
        account: String = "current-session",
        readSessionPayload: (() throws -> String?)? = nil,
        saveSessionPayload: ((String) throws -> Void)? = nil,
        deleteSessionPayload: (() throws -> Void)? = nil,
        webAuthentication: ((URL, String) async throws -> URL)? = nil
    ) {
        let processArguments = ProcessInfo.processInfo.arguments
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let authPersistenceDisabled = Self.shouldDisableAuthPersistence(
            arguments: processArguments,
            bundleIdentifier: bundleIdentifier
        )
        let authReadsEmpty = Self.shouldReturnEmptyAuthState(
            arguments: processArguments,
            bundleIdentifier: bundleIdentifier
        )
        self.session = session
        self.readSessionPayload = readSessionPayload ?? {
            guard !authReadsEmpty else { return nil }
            return try KeychainStore.read(service: service, account: account)
        }
        self.saveSessionPayload = saveSessionPayload ?? { payload in
            guard !authPersistenceDisabled else { return }
            try KeychainStore.save(payload, service: service, account: account)
        }
        self.deleteSessionPayload = deleteSessionPayload ?? {
            guard !authPersistenceDisabled else { return }
            try KeychainStore.delete(service: service, account: account)
        }
        self.webAuthenticationOverride = webAuthentication
        super.init()
    }

    static func allowsUITestAuthOverrides(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return developmentBundleIdentifiers.contains(bundleIdentifier)
    }

    static func shouldDisableAuthPersistence(
        arguments: [String],
        bundleIdentifier: String?
    ) -> Bool {
        allowsUITestAuthOverrides(bundleIdentifier: bundleIdentifier)
            && arguments.contains("UITEST_AUTH_NO_PERSIST")
    }

    static func shouldReturnEmptyAuthState(
        arguments: [String],
        bundleIdentifier: String?
    ) -> Bool {
        allowsUITestAuthOverrides(bundleIdentifier: bundleIdentifier)
            && (arguments.contains("UITEST_AUTH_EMPTY")
                || arguments.contains("UITEST_AUTH_NO_PERSIST"))
    }

    func restoreSession() -> AuthSession? {
        try? restoreSessionOrThrow()
    }

    func restoreSessionOrThrow() throws -> AuthSession? {
        let payload: String?
        do {
            payload = try readSessionPayload()
        } catch {
            throw KeychainStore.userVisibleError(for: error)
        }
        guard let payload,
              let data = payload.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            // Preserve unreadable credentials for explicit recovery instead of
            // silently treating them as absence and overwriting them.
            throw KeychainStore.userVisibleError(for: KeychainStoreError(operation: .read, status: nil, isCorrupt: true))
        }
    }

    func signIn(
        email: String,
        password: String,
        config: AppConfig,
        persist: Bool = true
    ) async throws -> AuthSession {
        guard !email.isEmpty, !password.isEmpty else { throw UserVisibleError.authenticationFailed }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            bearerToken: nil,
            body: [
                "email": email,
                "password": password
            ]
        )
        let session = try store(response: response, fallbackEmail: email, persist: persist)
        return session
    }

    func signUp(
        email: String,
        password: String,
        config: AppConfig,
        persist: Bool = true
    ) async throws -> AuthSession {
        guard !email.isEmpty, !password.isEmpty else { throw UserVisibleError.authenticationFailed }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/signup",
            bearerToken: nil,
            body: [
                "email": email,
                "password": password
            ],
            decodesSignupUser: true
        )
        if response.accessToken == nil, response.user != nil {
            throw UserVisibleError.emailConfirmationRequired
        }
        return try store(response: response, fallbackEmail: email, persist: persist)
    }

    func requestPasswordReset(email: String, config: AppConfig) async throws {
        guard !email.isEmpty else { throw UserVisibleError.authenticationFailed }
        guard let redirectURL = URL(string: Self.passwordResetWebURLString) else {
            throw UserVisibleError.malformedResponse
        }
        _ = try await requestAuth(
            config: config,
            path: "/auth/v1/recover",
            query: [URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString)],
            bearerToken: nil,
            body: ["email": email]
        )
    }

    func refreshStoredSession(config: AppConfig) async throws -> AuthSession? {
        guard let existing = try restoreSessionOrThrow() else { return nil }
        guard config.hasUsableSupabaseAuthConfiguration else {
            throw UserVisibleError.missingAuthConfiguration
        }
        if let expiresAt = existing.expiresAt, expiresAt.timeIntervalSinceNow > 60 {
            return existing
        }
        guard let refreshToken = existing.refreshToken, !refreshToken.isEmpty else {
            if isProvablyUnexpired(existing) {
                return existing
            }
            throw Self.expiredSessionError
        }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            bearerToken: nil,
            body: ["refresh_token": refreshToken],
            expiredSessionFailure: true
        )
        return try store(response: response, fallbackEmail: existing.email)
    }

    func signInWithApple(
        identityToken: Data,
        rawNonce: String,
        config: AppConfig,
        persist: Bool = true
    ) async throws -> AppleSignInResult {
        guard let token = String(data: identityToken, encoding: .utf8), !token.isEmpty else {
            throw UserVisibleError.authenticationFailed
        }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "id_token")],
            bearerToken: nil,
            body: [
                "provider": "apple",
                "id_token": token,
                "nonce": rawNonce
            ]
        )
        let session = try store(
            response: response,
            fallbackEmail: response.user?.email ?? "Apple user",
            persist: persist
        )
        return AppleSignInResult(session: session, isNewUser: Self.appleNewUserSignal(from: response.user))
    }

    func loadProviderConfiguration(config: AppConfig) async throws -> AuthProviderConfiguration {
        guard config.hasUsableAccountConfiguration,
              let supabaseURL = config.supabaseURL,
              let publishableKey = config.supabasePublishableKey else {
            throw UserVisibleError.missingAuthConfiguration
        }
        let url = supabaseURL.appending(path: "auth/v1/settings")
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw UserVisibleError.timeout
        } catch {
            throw UserVisibleError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw UserVisibleError.oauthProviderUnavailable
        }
        do {
            let settings = try JSONDecoder().decode(SupabaseAuthSettings.self, from: data)
            return AuthProviderConfiguration(
                apple: settings.external["apple"] == true,
                google: settings.external["google"] == true
            )
        } catch {
            throw UserVisibleError.malformedResponse
        }
    }

    func signInWithGoogle(config: AppConfig, persist: Bool = true) async throws -> AuthSession {
        let verifier = Self.randomURLSafeToken(byteCount: 48)
        let state = Self.randomURLSafeToken(byteCount: 32)
        let transaction = try Self.googleOAuthTransaction(
            config: config,
            state: state,
            codeVerifier: verifier
        )
        guard let callbackScheme = transaction.callbackURL.scheme else {
            throw UserVisibleError.malformedResponse
        }
        let callback: URL
        do {
            if let webAuthenticationOverride {
                callback = try await webAuthenticationOverride(
                    transaction.authorizationURL,
                    callbackScheme
                )
            } else {
                callback = try await authenticateUsingWebSession(
                    url: transaction.authorizationURL,
                    callbackScheme: callbackScheme
                )
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw UserVisibleError.googleSignInCancelled
        } catch is CancellationError {
            throw CancellationError()
        } catch let visible as UserVisibleError {
            throw visible
        } catch {
            throw UserVisibleError.authenticationFailed
        }

        let code = try Self.validatedGoogleOAuthCode(
            callback,
            expectedState: transaction.state,
            callbackScheme: callbackScheme
        )
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "pkce")],
            bearerToken: nil,
            body: [
                "auth_code": code,
                "code_verifier": transaction.codeVerifier,
            ]
        )
        return try store(
            response: response,
            fallbackEmail: response.user?.email ?? "Google user",
            persist: persist
        )
    }

    func signOut() throws {
        do {
            try deleteSessionPayload()
        } catch {
            throw KeychainStore.userVisibleError(for: error)
        }
    }

    /// Revokes the current Supabase access token, then always attempts local
    /// Keychain removal. Secure-storage deletion failures are surfaced so the
    /// caller can preserve a bounded retry marker instead of claiming success.
    func signOut(config: AppConfig) async throws {
        let existing = try restoreSessionOrThrow()
        var remoteError: Error?
        if let existing {
            guard config.hasUsableAccountConfiguration,
                  let supabaseURL = config.supabaseURL,
                  let publishableKey = config.supabasePublishableKey else {
                try signOut()
                throw UserVisibleError.missingAuthConfiguration
            }
            let url = supabaseURL.appending(path: "auth/v1/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(existing.accessToken)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw UserVisibleError.authenticationFailed
                }
            } catch let visible as UserVisibleError {
                remoteError = visible
            } catch let error as URLError where error.code == .timedOut {
                remoteError = UserVisibleError.timeout
            } catch is CancellationError {
                remoteError = CancellationError()
            } catch {
                remoteError = UserVisibleError.networkUnavailable
            }
        }
        try signOut()
        if let remoteError { throw remoteError }
    }

    func deleteStoredAuth() throws {
        try signOut()
    }

    /// Stores a previously authenticated session only after the user has
    /// explicitly chosen how existing guest practice should be handled.
    func persistSession(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw UserVisibleError.malformedResponse
        }
        do {
            try saveSessionPayload(payload)
        } catch {
            throw KeychainStore.userVisibleError(for: error)
        }
    }

    func appleNonce() -> String {
        Self.randomNonce()
    }

    static func randomNonce() -> String {
        randomURLSafeToken(byteCount: 32)
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func resolvedOAuthCallbackScheme(
        rawValue: String?,
        bundleIdentifier: String?
    ) -> String? {
        let expectedScheme: String
        if bundleIdentifier == productionBundleIdentifier {
            expectedScheme = productionOAuthCallbackScheme
        } else if let bundleIdentifier,
                  developmentBundleIdentifiers.contains(bundleIdentifier) {
            expectedScheme = developmentOAuthCallbackScheme
        } else {
            return nil
        }
        guard let candidate = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              candidate == expectedScheme else {
            return nil
        }
        return expectedScheme
    }

    static func googleOAuthTransaction(
        config: AppConfig,
        state: String,
        codeVerifier: String,
        callbackScheme: String? = oauthCallbackScheme
    ) throws -> GoogleOAuthTransaction {
        guard let callbackScheme,
              let runtimeCallbackScheme = oauthCallbackScheme,
              callbackScheme == runtimeCallbackScheme else {
            throw UserVisibleError.oauthCallbackInvalid
        }
        guard config.hasUsableAccountConfiguration,
              let supabaseURL = config.supabaseURL,
              !state.isEmpty,
              (43...128).contains(codeVerifier.count) else {
            throw UserVisibleError.missingAuthConfiguration
        }
        let challenge = base64URLEncoded(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
        var callbackComponents = URLComponents()
        callbackComponents.scheme = callbackScheme
        callbackComponents.host = googleOAuthCallbackHost
        callbackComponents.path = googleOAuthCallbackPath
        callbackComponents.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let callbackURL = callbackComponents.url else {
            throw UserVisibleError.malformedResponse
        }

        var authorizationComponents = URLComponents(
            url: supabaseURL.appending(path: "auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )
        authorizationComponents?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: callbackURL.absoluteString),
            URLQueryItem(name: "scopes", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let authorizationURL = authorizationComponents?.url,
              authorizationURL.scheme == "https",
              authorizationURL.host == supabaseURL.host else {
            throw UserVisibleError.malformedResponse
        }
        return GoogleOAuthTransaction(
            authorizationURL: authorizationURL,
            callbackURL: callbackURL,
            state: state,
            codeVerifier: codeVerifier
        )
    }

    static func validatedGoogleOAuthCode(
        _ callbackURL: URL,
        expectedState: String,
        callbackScheme: String? = oauthCallbackScheme
    ) throws -> String {
        guard let callbackScheme,
              let runtimeCallbackScheme = oauthCallbackScheme,
              callbackScheme == runtimeCallbackScheme,
              callbackURL.scheme?.lowercased() == callbackScheme,
              callbackURL.host?.lowercased() == googleOAuthCallbackHost,
              callbackURL.path == googleOAuthCallbackPath,
              callbackURL.user == nil,
              callbackURL.password == nil,
              callbackURL.port == nil,
              callbackURL.fragment == nil,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw UserVisibleError.oauthCallbackInvalid
        }
        let queryItems = components.queryItems ?? []
        let allowedNames = Set(["code", "state", "error", "error_code", "error_description"])
        guard queryItems.allSatisfy({ allowedNames.contains($0.name) }),
              queryItems.filter({ $0.name == "state" }).count == 1,
              queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            throw UserVisibleError.oauthCallbackInvalid
        }
        if queryItems.contains(where: { $0.name == "error" }) {
            throw UserVisibleError.googleSignInCancelled
        }
        guard queryItems.filter({ $0.name == "code" }).count == 1,
              let code = queryItems.first(where: { $0.name == "code" })?.value,
              (1...4_096).contains(code.count),
              code.unicodeScalars.allSatisfy({
                  !CharacterSet.whitespacesAndNewlines.contains($0)
                      && !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw UserVisibleError.oauthCallbackInvalid
        }
        return code
    }

    static func randomURLSafeToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: max(16, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // UUID entropy is a bounded last-resort fallback. The OAuth flow
            // still binds the callback to ASWebAuthenticationSession and PKCE.
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return base64URLEncoded(Data(bytes))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func authenticateUsingWebSession(
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
                self?.webAuthenticationSession = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: UserVisibleError.oauthCallbackInvalid)
                }
            }
            let authenticationSession: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                authenticationSession = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(callbackScheme),
                    completionHandler: completion
                )
            } else {
                authenticationSession = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme,
                    completionHandler: completion
                )
            }
            authenticationSession.presentationContextProvider = self
            webAuthenticationSession = authenticationSession
            guard authenticationSession.start() else {
                webAuthenticationSession = nil
                continuation.resume(throwing: UserVisibleError.oauthProviderUnavailable)
                return
            }
        }
    }

    func accessToken() throws -> String? {
        try restoreSessionOrThrow()?.accessToken
    }

    func validAccessToken(config: AppConfig) async throws -> String? {
        try await refreshStoredSession(config: config)?.accessToken
    }

    func unexpiredStoredSession() throws -> AuthSession? {
        guard let existing = try restoreSessionOrThrow(), isProvablyUnexpired(existing) else { return nil }
        return existing
    }

    private func isProvablyUnexpired(_ session: AuthSession) -> Bool {
        guard !session.accessToken.isEmpty, let expiresAt = session.expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow > 0
    }

    private func store(
        response: SupabaseAuthResponse,
        fallbackEmail: String,
        persist: Bool = true
    ) throws -> AuthSession {
        guard let accessToken = response.accessToken, !accessToken.isEmpty,
              let userID = response.user?.id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { throw UserVisibleError.authenticationFailed }
        let session = AuthSession(
            userID: userID,
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            email: response.user?.email ?? fallbackEmail,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        if persist {
            try persistSession(session)
        }
        return session
    }

    private func requestAuth(
        config: AppConfig,
        path: String,
        query: [URLQueryItem] = [],
        bearerToken: String?,
        body: [String: String],
        expiredSessionFailure: Bool = false,
        decodesSignupUser: Bool = false
    ) async throws -> SupabaseAuthResponse {
        guard config.hasUsableAccountConfiguration,
              let supabaseURL = config.supabaseURL,
              let publishableKey = config.supabasePublishableKey else {
            throw UserVisibleError.missingAuthConfiguration
        }
        var components = URLComponents(url: supabaseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw UserVisibleError.malformedResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw UserVisibleError.timeout
        } catch {
            throw UserVisibleError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 401
            if expiredSessionFailure {
                if statusCode == 408
                    || statusCode == 425
                    || statusCode == 429
                    || (500...599).contains(statusCode) {
                    throw UserVisibleError.apiRequestFailed(
                        statusCode: statusCode,
                        message: NativeLocalization.string("The account service couldn't refresh your sign-in right now. Your saved session will be retried later.")
                    )
                }
                throw UserVisibleError.apiRequestFailed(
                    statusCode: statusCode,
                    message: NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
                )
            }
            throw UserVisibleError.authenticationFailed
        }
        do {
            if decodesSignupUser {
                return try JSONDecoder().decode(SupabaseSignupResponse.self, from: data).authResponse
            }
            return try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        } catch {
            if data.isEmpty {
                return SupabaseAuthResponse(accessToken: nil, refreshToken: nil, expiresIn: nil, user: nil)
            }
            throw UserVisibleError.malformedResponse
        }
    }

    private static var expiredSessionError: UserVisibleError {
        .apiRequestFailed(
            statusCode: 401,
            message: NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
        )
    }

    private static func appleNewUserSignal(from user: SupabaseAuthUser?) -> Bool? {
        guard let createdAt = parseSupabaseDate(user?.createdAt),
              let lastSignInAt = parseSupabaseDate(user?.lastSignInAt) else {
            return nil
        }
        let ageAtSignIn = lastSignInAt.timeIntervalSince(createdAt)
        guard ageAtSignIn >= -1 else { return nil }
        return ageAtSignIn <= 5
    }

    private static func parseSupabaseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        if let keyWindow = activeScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let foregroundWindow = activeScenes.flatMap(\.windows).first {
            return foregroundWindow
        }
        return ASPresentationAnchor()
    }
}

enum KeychainStore {
    static let sessionAccessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    /// Replaces a credential in place.  Deleting before an add creates a data
    /// loss window: an unavailable Keychain would leave a user signed out even
    /// though their previous credential was still valid.
    static func save(
        _ value: String,
        service: String,
        account: String,
        update: ((CFDictionary, CFDictionary) -> OSStatus)? = nil,
        add: ((CFDictionary) -> OSStatus)? = nil
    ) throws {
        let data = Data(value.utf8)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: sessionAccessibility
        ]
        let updateItem = update ?? { query, attributes in
            SecItemUpdate(query, attributes)
        }
        let addItem = add ?? { query in
            SecItemAdd(query, nil)
        }

        let updateStatus = updateItem(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError(operation: .save, status: updateStatus)
        }

        var addQuery = identity
        attributes.forEach { addQuery[$0.key] = $0.value }
        let status = addItem(addQuery as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainStoreError(operation: .save, status: status)
        }
    }

    static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError(operation: .read, status: status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError(operation: .read, status: nil, isCorrupt: true)
        }
        return value
    }

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(operation: .delete, status: status)
        }
    }

    static func userVisibleError(for error: Error) -> UserVisibleError {
        if let error = error as? UserVisibleError { return error }
        guard let error = error as? KeychainStoreError else {
            return .secureStorageUnavailable
        }
        if error.isCorrupt { return .secureStorageCorrupt }
        if error.status == errSecMissingEntitlement || error.status == errSecNotAvailable {
            return .secureStorageUnavailable
        }
        switch error.operation {
        case .read: return .secureStorageReadFailed
        case .save: return .secureStorageSaveFailed
        case .delete: return .secureStorageDeletionFailed
        }
    }
}

enum KeychainOperation: Equatable {
    case read
    case save
    case delete
}

struct KeychainStoreError: Error, Equatable {
    let operation: KeychainOperation
    /// Retained for diagnosis only; neither the query nor credential payload is logged.
    let status: OSStatus?
    let isCorrupt: Bool

    init(operation: KeychainOperation, status: OSStatus?, isCorrupt: Bool = false) {
        self.operation = operation
        self.status = status
        self.isCorrupt = isCorrupt
    }
}

struct AuthSession: Codable, Equatable {
    let userID: String
    let accessToken: String
    let refreshToken: String?
    let email: String
    let expiresAt: Date?
}

struct AppleSignInResult: Equatable {
    let session: AuthSession
    /// `nil` means the server omitted timestamps needed to distinguish a new
    /// identity from a returning one. The app intentionally tours that case.
    let isNewUser: Bool?
}

struct AuthProviderConfiguration: Equatable {
    let apple: Bool
    let google: Bool
}

struct GoogleOAuthTransaction: Equatable {
    let authorizationURL: URL
    let callbackURL: URL
    let state: String
    let codeVerifier: String
}

private struct SupabaseAuthSettings: Decodable {
    let external: [String: Bool]
}

struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    init(accessToken: String?, refreshToken: String?, expiresIn: Int?, user: SupabaseAuthUser?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        user = try container.decodeIfPresent(SupabaseAuthUser.self, forKey: .user)
    }
}

/// `/auth/v1/signup` may return a confirmation-required UserSchema at the
/// top level. Keep that compatibility path scoped to sign-up rather than
/// accepting a top-level user for token, refresh, or OAuth responses.
private struct SupabaseSignupResponse: Decodable {
    let authResponse: SupabaseAuthResponse

    init(from decoder: Decoder) throws {
        let nestedResponse = try SupabaseAuthResponse(from: decoder)
        guard nestedResponse.user == nil else {
            authResponse = nestedResponse
            return
        }
        let topLevelUser = try SupabaseAuthUser(from: decoder)
        if topLevelUser.hasIdentityFields,
           (nestedResponse.accessToken != nil || nestedResponse.refreshToken != nil) {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "A signup response must not combine session tokens with a top-level user."
                )
            )
        }
        authResponse = SupabaseAuthResponse(
            accessToken: nestedResponse.accessToken,
            refreshToken: nestedResponse.refreshToken,
            expiresIn: nestedResponse.expiresIn,
            user: topLevelUser.hasIdentityFields ? topLevelUser : nil
        )
    }
}

struct SupabaseAuthUser: Decodable {
    let id: String?
    let email: String?
    let createdAt: String?
    let lastSignInAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case lastSignInAt = "last_sign_in_at"
    }

    var hasIdentityFields: Bool {
        id != nil || email != nil || createdAt != nil || lastSignInAt != nil
    }
}
