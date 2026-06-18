import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
final class AuthService: NSObject {
    private let service = "com.brasstune.auth"
    private let account = "current-session"

    func restoreSession() -> AuthSession? {
        guard let payload = KeychainStore.read(service: service, account: account),
              let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
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
        guard let existing = restoreSession(), let refreshToken = existing.refreshToken else {
            return restoreSession()
        }
        if let expiresAt = existing.expiresAt, expiresAt.timeIntervalSinceNow > 60 {
            return existing
        }
        let response = try await requestAuth(
            config: config,
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            bearerToken: nil,
            body: ["refresh_token": refreshToken]
        )
        return try store(response: response, fallbackEmail: existing.email)
    }

    func signInWithApple(identityToken: Data, rawNonce: String, config: AppConfig) async throws -> AuthSession {
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
        return try store(response: response, fallbackEmail: response.user?.email ?? "Apple user")
    }

    func signOut() {
        KeychainStore.delete(service: service, account: account)
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

    private func store(response: SupabaseAuthResponse, fallbackEmail: String) throws -> AuthSession {
        guard let accessToken = response.accessToken, !accessToken.isEmpty else { throw UserVisibleError.authenticationFailed }
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: response.refreshToken,
            email: response.user?.email ?? fallbackEmail,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
        let data = try JSONEncoder().encode(session)
        guard let payload = String(data: data, encoding: .utf8) else { throw UserVisibleError.malformedResponse }
        try KeychainStore.save(payload, service: service, account: account)
        return session
    }

    private func requestAuth(
        config: AppConfig,
        path: String,
        query: [URLQueryItem] = [],
        bearerToken: String?,
        body: [String: String]
    ) async throws -> SupabaseAuthResponse {
        guard let supabaseURL = config.supabaseURL,
              let publishableKey = config.supabasePublishableKey,
              !publishableKey.isEmpty else {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
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
}

enum KeychainStore {
    static func save(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw UserVisibleError.networkUnavailable }
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
    let accessToken: String
    let refreshToken: String?
    let email: String
    let expiresAt: Date?
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
    let email: String?
}
