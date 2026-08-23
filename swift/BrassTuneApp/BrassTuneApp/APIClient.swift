import Foundation

struct APIClient {
    var timeout: TimeInterval = 15
    var session: URLSession = .shared

    func request<T: Decodable>(
        _ type: T.Type,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: AppConfig,
        bearerToken: String? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        guard config.hasUsableAPIConfiguration else {
            throw UserVisibleError.apiRequestFailed(statusCode: 0, message: NativeLocalization.string("The class service address is not approved for this build."))
        }
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: config.apiBaseURL)?.absoluteURL,
              url.scheme?.lowercased() == config.apiBaseURL.scheme?.lowercased(),
              url.host?.lowercased() == config.apiBaseURL.host?.lowercased(),
              url.port == config.apiBaseURL.port,
              url.user == nil,
              url.password == nil else {
            throw UserVisibleError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        if body != nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw UserVisibleError.timeout
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UserVisibleError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw UserVisibleError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UserVisibleError.apiRequestFailed(statusCode: http.statusCode, message: Self.safeMessage(data: data, statusCode: http.statusCode))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw UserVisibleError.malformedResponse
        }
    }

    func data(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: AppConfig,
        bearerToken: String,
        contentType: String? = nil
    ) async throws -> Data {
        guard config.hasUsableAPIConfiguration,
              path.hasPrefix("/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: config.apiBaseURL)?.absoluteURL,
              url.host?.lowercased() == config.apiBaseURL.host?.lowercased(),
              url.scheme?.lowercased() == config.apiBaseURL.scheme?.lowercased(),
              url.port == config.apiBaseURL.port else { throw UserVisibleError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UserVisibleError.malformedResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw UserVisibleError.apiRequestFailed(statusCode: http.statusCode, message: Self.safeMessage(data: data, statusCode: http.statusCode))
            }
            return data
        } catch let visible as UserVisibleError { throw visible }
        catch let error as URLError where error.code == .timedOut { throw UserVisibleError.timeout }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw UserVisibleError.networkUnavailable }
    }

    private static func safeMessage(data: Data, statusCode: Int) -> String {
        struct Envelope: Decodable { let detail: String? }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: data))?.detail
        let approved = [
            "Username is already taken.",
            "Choose a JPEG or PNG profile photo.",
            "Profile photo must be 5 MB or smaller.",
            "The profile photo does not match its file type.",
            "Profile photo dimensions are too large.",
            "The profile photo could not be decoded safely.",
            "Profile photo is unavailable."
        ]
        if let detail, approved.contains(detail) { return NativeLocalization.preserve(detail) }
        return fallbackMessage(for: statusCode)
    }

    private static func fallbackMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401: return NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
        case 403: return NativeLocalization.string("You don't have permission to do that.")
        case 404: return NativeLocalization.string("The requested information could not be found.")
        case 409: return NativeLocalization.string("That change conflicts with existing account information.")
        case 413: return NativeLocalization.string("That upload is too large.")
        case 415: return NativeLocalization.string("That file type is not supported.")
        case 429: return NativeLocalization.string("Too many requests. Wait a moment, then try again.")
        default: return NativeLocalization.string("The BrassTune service could not complete this request.")
        }
    }
}
