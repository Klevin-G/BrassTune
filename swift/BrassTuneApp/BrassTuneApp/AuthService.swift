import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class AuthService: NSObject {
    static let oauthCallbackScheme = "com.brasstune.auth"
    static let googleOAuthCallbackHost = "oauth"
    static let googleOAuthCallbackPath = "/google"

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
        self.session = session
        self.readSessionPayload = readSessionPayload ?? {
            if ProcessInfo.processInfo.arguments.contains("UITEST_AUTH_EMPTY") {
                return nil
            }
            return try KeychainStore.read(service: service, account: account)
        }
        self.saveSessionPayload = saveSessionPayload ?? { payload in
            try KeychainStore.save(payload, service: service, account: account)
        }
        self.deleteSessionPayload = deleteSessionPayload ?? {
            try KeychainStore.delete(service: service, account: account)
        }
        self.webAuthenticationOverride = webAuthentication
        super.init()
    }

    func restoreSession() -> AuthSession? {
        try? restoreSessionOrThrow()
    }

    func restoreSessionOrThrow() throws -> AuthSession? {
        guard let payload = try readSessionPayload(),
              let data = payload.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            // Preserve unreadable credentials for explicit recovery instead of
            // silently treating them as absence and overwriting them.
            throw UserVisibleError.secureStorageUnavailable
        }
    }

    func signIn(email: String, password: String, config: AppConfig) async throws -> AuthSession {
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
        let session = try store(response: response, fallbackEmail: email)
        return session
    }

    func signUp(email: String, password: String, config: AppConfig) async throws -> AuthSession {
        guard !email.isEmpty, !password.isEmpty else { throw UserVisibleError.authenticationFailed }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/signup",
            bearerToken: nil,
            body: [
                "email": email,
                "password": password
            ]
        )
        if response.accessToken == nil, response.user?.email != nil {
            throw UserVisibleError.emailConfirmationRequired
        }
        return try store(response: response, fallbackEmail: email)
    }

    func requestPasswordReset(email: String, config: AppConfig) async throws {
        guard !email.isEmpty else { throw UserVisibleError.authenticationFailed }
        _ = try await requestAuth(
            config: config,
            path: "/auth/v1/recover",
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

    func signInWithApple(identityToken: Data, rawNonce: String, config: AppConfig) async throws -> AppleSignInResult {
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
        let session = try store(response: response, fallbackEmail: response.user?.email ?? "Apple user")
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

    func signInWithGoogle(config: AppConfig) async throws -> AuthSession {
        let verifier = Self.randomURLSafeToken(byteCount: 48)
        let state = Self.randomURLSafeToken(byteCount: 32)
        let transaction = try Self.googleOAuthTransaction(
            config: config,
            state: state,
            codeVerifier: verifier
        )
        let callback: URL
        do {
            if let webAuthenticationOverride {
                callback = try await webAuthenticationOverride(
                    transaction.authorizationURL,
                    Self.oauthCallbackScheme
                )
            } else {
                callback = try await authenticateUsingWebSession(
                    url: transaction.authorizationURL,
                    callbackScheme: Self.oauthCallbackScheme
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
            expectedState: transaction.state
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
        return try store(response: response, fallbackEmail: response.user?.email ?? "Google user")
    }

    func signOut() throws {
        do {
            try deleteSessionPayload()
        } catch {
            throw UserVisibleError.secureStorageDeletionFailed
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

    func appleNonce() -> String {
        Self.randomNonce()
    }

    static func randomNonce() -> String {
        randomURLSafeToken(byteCount: 32)
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func googleOAuthTransaction(
        config: AppConfig,
        state: String,
        codeVerifier: String
    ) throws -> GoogleOAuthTransaction {
        guard config.hasUsableAccountConfiguration,
              let supabaseURL = config.supabaseURL,
              !state.isEmpty,
              (43...128).contains(codeVerifier.count) else {
            throw UserVisibleError.missingAuthConfiguration
        }
        let challenge = base64URLEncoded(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
        var callbackComponents = URLComponents()
        callbackComponents.scheme = oauthCallbackScheme
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
        expectedState: String
    ) throws -> String {
        guard callbackURL.scheme?.lowercased() == oauthCallbackScheme,
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
            authenticationSession.prefersEphemeralWebBrowserSession = true
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

    private func store(response: SupabaseAuthResponse, fallbackEmail: String) throws -> AuthSession {
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
        let data = try JSONEncoder().encode(session)
        guard let payload = String(data: data, encoding: .utf8) else { throw UserVisibleError.malformedResponse }
        try saveSessionPayload(payload)
        return session
    }

    private func requestAuth(
        config: AppConfig,
        path: String,
        query: [URLQueryItem] = [],
        bearerToken: String?,
        body: [String: String],
        expiredSessionFailure: Bool = false
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

    static func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        try delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: sessionAccessibility
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw UserVisibleError.secureStorageUnavailable }
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
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw UserVisibleError.secureStorageUnavailable
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
            throw UserVisibleError.secureStorageDeletionFailed
        }
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
}
