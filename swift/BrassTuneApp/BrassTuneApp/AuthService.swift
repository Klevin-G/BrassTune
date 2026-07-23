import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
final class AuthService: NSObject {
    private let session: URLSession
    private let readSessionPayload: () -> String?
    private let saveSessionPayload: (String) throws -> Void
    private let deleteSessionPayload: () -> Void

    init(
        session: URLSession = .shared,
        service: String = "com.brasstune.auth",
        account: String = "current-session",
        readSessionPayload: (() -> String?)? = nil,
        saveSessionPayload: ((String) throws -> Void)? = nil,
        deleteSessionPayload: (() -> Void)? = nil
    ) {
        self.session = session
        self.readSessionPayload = readSessionPayload ?? {
            KeychainStore.read(service: service, account: account)
        }
        self.saveSessionPayload = saveSessionPayload ?? { payload in
            try KeychainStore.save(payload, service: service, account: account)
        }
        self.deleteSessionPayload = deleteSessionPayload ?? {
            KeychainStore.delete(service: service, account: account)
        }
        super.init()
    }

    func restoreSession() -> AuthSession? {
        guard let payload = readSessionPayload(),
              let data = payload.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            // Legacy/corrupt payloads may not contain the stable user ID that
            // now defines the local storage namespace. Fail closed and remove
            // the unusable token instead of leaving it recoverable in Keychain.
            deleteSessionPayload()
            return nil
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
        guard let existing = restoreSession() else { return nil }
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

    func signOut() {
        deleteSessionPayload()
    }

    /// Revokes the current Supabase access token before removing the local
    /// Keychain payload. Local removal is guaranteed even when the device is
    /// offline, so a failed network request never leaves a reusable token here.
    func signOut(config: AppConfig) async throws {
        let existing = restoreSession()
        defer { deleteSessionPayload() }
        guard let existing else { return }
        guard config.hasUsableAccountConfiguration,
              let supabaseURL = config.supabaseURL,
              let publishableKey = config.supabasePublishableKey else {
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
            throw visible
        } catch let error as URLError where error.code == .timedOut {
            throw UserVisibleError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UserVisibleError.networkUnavailable
        }
    }

    func deleteStoredAuth() {
        signOut()
    }

    func appleNonce() -> String {
        Self.randomNonce()
    }

    static func randomNonce() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func accessToken() -> String? {
        restoreSession()?.accessToken
    }

    func validAccessToken(config: AppConfig) async throws -> String? {
        try await refreshStoredSession(config: config)?.accessToken
    }

    func unexpiredStoredSession() -> AuthSession? {
        guard let existing = restoreSession(), isProvablyUnexpired(existing) else { return nil }
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
                        message: "The account service couldn't refresh your sign-in right now. Your saved session will be retried later."
                    )
                }
                throw UserVisibleError.apiRequestFailed(
                    statusCode: statusCode,
                    message: "Your sign-in expired. Sign in again, then retry."
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

    private static let expiredSessionError = UserVisibleError.apiRequestFailed(
        statusCode: 401,
        message: "Your sign-in expired. Sign in again, then retry."
    )

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

enum KeychainStore {
    static let sessionAccessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    static func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        delete(service: service, account: account)
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

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
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
