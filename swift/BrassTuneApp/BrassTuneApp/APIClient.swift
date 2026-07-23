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
        bearerToken: String? = nil
    ) async throws -> T {
        guard config.hasUsableAPIConfiguration else {
            throw UserVisibleError.apiRequestFailed(statusCode: 0, message: "The class service address is not approved for this build.")
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
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.userSafeDetail
            throw UserVisibleError.apiRequestFailed(
                statusCode: http.statusCode,
                message: detail ?? Self.fallbackMessage(for: http.statusCode)
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw UserVisibleError.malformedResponse
        }
    }

    private static func fallbackMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401: return NativeLocalization.string("Your sign-in expired. Sign in again, then retry.")
        case 403: return NativeLocalization.string("You don't have permission to do that.")
        case 404: return NativeLocalization.string("That class could not be found.")
        case 409: return NativeLocalization.string("That class action conflicts with your current membership.")
        default: return NativeLocalization.string("The class service could not complete this request.")
        }
    }
}

private struct APIErrorResponse: Decodable {
    let detail: Detail?

    var userSafeDetail: String? {
        let raw: String?
        switch detail {
        case .message(let message): raw = message
        case .validation(let issues): raw = issues.prefix(2).map(\.message).joined(separator: " ")
        case nil: raw = nil
        }
        guard let raw else { return nil }
        let normalized = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(240))
    }

    enum Detail: Decodable {
        case message(String)
        case validation([ValidationIssue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let message = try? container.decode(String.self) {
                self = .message(message)
                return
            }
            self = .validation(try container.decode([ValidationIssue].self))
        }
    }

    struct ValidationIssue: Decodable {
        let message: String

        enum CodingKeys: String, CodingKey {
            case message = "msg"
        }
    }
}
