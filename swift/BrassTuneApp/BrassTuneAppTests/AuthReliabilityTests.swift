import CryptoKit
import XCTest
@testable import BrassTuneApp

/// Counts and answers every request an `AuthService` under test sends, so a
/// test can prove how many network exchanges a callback caused.
private final class AuthReliabilityURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class AuthReliabilityTests: XCTestCase {
    @MainActor
    func testGoogleCallbackOnlyTreatsAccessDeniedAsUserCancellation() throws {
        guard let callbackScheme = AuthService.oauthCallbackScheme else {
            throw XCTSkip("The test host does not register an approved callback scheme.")
        }

        let cancelled = try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?state=expected&error=access_denied"))
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                cancelled,
                expectedState: "expected",
                callbackScheme: callbackScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .googleSignInCancelled)
        }

        let providerFailure = try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?state=expected&error=server_error"))
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                providerFailure,
                expectedState: "expected",
                callbackScheme: callbackScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .oauthProviderUnavailable)
        }
    }

    @MainActor
    func testGoogleProviderErrorsAcceptOnlyMirroredSupabaseFragments() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let base = "\(callbackScheme)://oauth/google?state=expected"
        let liveCancellation = try XCTUnwrap(URL(string: "\(base)&error=access_denied&error_description=User%20cancelled#error=access_denied&error_description=User%20cancelled&sb="))
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                liveCancellation,
                expectedState: "expected",
                callbackScheme: callbackScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .googleSignInCancelled)
        }

        let liveProviderFailure = try XCTUnwrap(URL(string: "\(base)&error=server_error&error_description=Provider%20unavailable#error=server_error&error_description=Provider%20unavailable&sb="))
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                liveProviderFailure,
                expectedState: "expected",
                callbackScheme: callbackScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .oauthProviderUnavailable)
        }

        let percentEquivalentCancellation = try XCTUnwrap(URL(string: "\(base)&error=access_denied&error_description=User%2Ecancelled&error_code=403#error=access_denied&error_description=User.cancelled&error_code=403&sb="))
        XCTAssertThrowsError(
            try AuthService.validatedGoogleOAuthCode(
                percentEquivalentCancellation,
                expectedState: "expected",
                callbackScheme: callbackScheme
            )
        ) { error in
            XCTAssertEqual(error as? UserVisibleError, .googleSignInCancelled)
        }

        for invalid in [
            "\(base)&error=access_denied#error=server_error&sb=",
            "\(base)&error=access_denied#error=access_denied&error=access_denied&sb=",
            "\(base)&error=access_denied#error=access_denied&sb=&extra=value",
            "\(base)&error=access_denied#error=access_denied&sb=&access_token=token",
            "\(base)&code=one-time-code#sb=",
            "\(base)&error=access_denied&error_description=one&error_description=two",
            "\(base)&error=access_denied&error_code=one&error_code=two",
            "\(base)&error=access_denied&error_description=User%20cancelled#error=access_denied&sb=",
            "\(base)&error=access_denied#error=access_denied&error_description=User%20cancelled&sb=",
            "\(base)&error=access_denied&error_description=User%20cancelled#error=access_denied&error_description=User%20rejected&sb=",
            "\(base)&error=access_denied&error_description=one#error=access_denied&error_description=one&error_description=one&sb=",
            "\(base)&error=access_denied&error_code=one#error=access_denied&error_code=one&error_code=one&sb=",
            "\(base)&error=access_denied#error=access_denied&sb=&sb=",
            "\(base)&error=access_denied#error=access_denied",
        ] {
            let url = try XCTUnwrap(URL(string: invalid))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(
                    url,
                    expectedState: "expected",
                    callbackScheme: callbackScheme
                ),
                invalid
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid)
            }
        }
    }

    /// Error redirects captured from the live Supabase Auth (GoTrue v2.197.0)
    /// on 2026-09-29 for this project's allow-listed callback. The fragment
    /// omits an empty description and double-encodes `:` and `/`.
    @MainActor
    func testGoogleProviderErrorsAcceptLiveCapturedSupabaseMirrorShapes() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let prefix = "\(callbackScheme)://oauth/google?"
        let cases: [(String, UserVisibleError)] = [
            ("error=access_denied&error_description=&state=expected#error=access_denied&sb=", .googleSignInCancelled),
            ("error=access_denied&error_description=The+user+denied&state=expected#error=access_denied&error_description=The+user+denied&sb=", .googleSignInCancelled),
            ("error=server_error&error_code=unexpected_failure&error_description=Unable+to+exchange+external+code%3A+4%2Fbo&state=expected#error=server_error&error_code=unexpected_failure&error_description=Unable+to+exchange+external+code%253A+4%252Fbo&sb=", .oauthProviderUnavailable),
        ]
        for (suffix, expected) in cases {
            let url = try XCTUnwrap(URL(string: prefix + suffix))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                suffix
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, expected, suffix)
            }
        }
        // The mirror must still agree after one decoding step.
        for invalid in [
            "error=server_error&error_code=unexpected_failure&state=expected#error=server_error&error_code=other_failure&sb=",
            "error=server_error&error_description=A%3AB&state=expected#error=server_error&error_description=A%253AC&sb=",
            "error=access_denied&error_description=&state=expected#error=access_denied&error_description=injected&sb=",
        ] {
            let url = try XCTUnwrap(URL(string: prefix + invalid))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                invalid
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid, invalid)
            }
        }
    }

    /// A bare trailing `#` contains no provider data. Foundation exposes it as
    /// an empty, non-nil fragment, so provider errors must treat it as absent
    /// just as the success callback does. Nonempty mirrors remain covered by
    /// the strict tests above.
    @MainActor
    func testGoogleProviderErrorsAcceptAbsentOrExactlyEmptyFragment() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let prefix = "\(callbackScheme)://oauth/google?state=expected"
        for (query, expected) in [
            ("error=access_denied", UserVisibleError.googleSignInCancelled),
            ("error=access_denied#", UserVisibleError.googleSignInCancelled),
            ("error=server_error", UserVisibleError.oauthProviderUnavailable),
            ("error=server_error#", UserVisibleError.oauthProviderUnavailable),
        ] {
            let url = try XCTUnwrap(URL(string: "\(prefix)&\(query)"))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme)
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, expected, query)
            }
        }
    }

    @MainActor
    func testGoogleCallbackRejectionReasonsAreFixedAndValueFree() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let expectedState = "expected-state-secret"
        let fixtures: [(String, GoogleOAuthCallbackFailureReason)] = [
            ("other.scheme://oauth/google?state=\(expectedState)&code=code", .callbackScheme),
            ("\(callbackScheme)://other/google?state=\(expectedState)&code=code", .callbackHost),
            ("\(callbackScheme)://oauth/other?state=\(expectedState)&code=code", .callbackPath),
            ("\(callbackScheme)://user@oauth/google?state=\(expectedState)&code=code", .callbackAuthority),
            ("\(callbackScheme)://oauth/google?state=\(expectedState)&code=code&extra=secret", .callbackQueryNames),
            ("\(callbackScheme)://oauth/google?code=code", .callbackStateCount),
            ("\(callbackScheme)://oauth/google?state=other-secret&code=code", .callbackStateMismatch),
            ("\(callbackScheme)://oauth/google?state=\(expectedState)&error=access_denied#sb=", .callbackProviderErrorShape),
            ("\(callbackScheme)://oauth/google?state=\(expectedState)&code=code#nonempty", .callbackFragment),
            ("\(callbackScheme)://oauth/google?state=\(expectedState)&code=one&code=two", .callbackSuccessShape),
            ("\(callbackScheme)://oauth/google?state=\(expectedState)&code=", .callbackCode),
        ]
        for (text, expected) in fixtures {
            let reason = AuthService.googleCallbackRejectionReason(
                try XCTUnwrap(URL(string: text)),
                expectedState: expectedState,
                callbackScheme: callbackScheme
            )
            XCTAssertEqual(reason, expected, text)
            let diagnostic = GoogleOAuthCallbackDiagnostic(reason: reason)
            XCTAssertTrue(diagnostic.reference.hasPrefix("GCB-"), diagnostic.reference)
            XCTAssertFalse(diagnostic.userMessage.contains("expected-state-secret"), diagnostic.userMessage)
            XCTAssertFalse(diagnostic.userMessage.contains("other-secret"), diagnostic.userMessage)
            XCTAssertFalse(diagnostic.userMessage.contains("extra"), diagnostic.userMessage)
        }
    }

    /// A success callback carries exactly one state and one code. Error
    /// fields beside a code are contradictory and must fail closed.
    @MainActor
    func testGoogleSuccessCallbackRejectsContradictoryErrorFields() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let valid = try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?code=one-time-code&state=expected"))
        XCTAssertEqual(
            try AuthService.validatedGoogleOAuthCode(valid, expectedState: "expected", callbackScheme: callbackScheme),
            "one-time-code"
        )
        for invalid in [
            "code=one-time-code&state=expected&error_code=unexpected_failure",
            "code=one-time-code&state=expected&error_description=Provider+failure",
            "code=one-time-code&state=expected&error_code=a&error_description=b",
            "code=one-time-code&code=second-code&state=expected",
            "code=one-time-code&state=expected&state=expected",
            "code=one-time-code&state=expected#sb=",
        ] {
            let url = try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?\(invalid)"))
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                invalid
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid, invalid)
            }
        }
    }

    /// The rejection diagnostic reports fixed categories only. Unknown
    /// parameter names and every parameter value stay out of the log line.
    @MainActor
    func testGoogleCallbackShapeSummaryNeverContainsCallbackNamesOrValues() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let secrets = [
            "expected-state-secret", "one-time-code-secret", "access_token", "refresh_token",
            "eyJhbGciOiJIUzI1NiJ9", "sbp_0123456789abcdef", "provider_token", "tokenvalue123",
            "Provider+failure", "verifier",
        ]
        let hostile = try XCTUnwrap(URL(string:
            "\(callbackScheme)://oauth/google?state=expected-state-secret&code=one-time-code-secret"
            + "&access_token=eyJhbGciOiJIUzI1NiJ9&sbp_0123456789abcdef=tokenvalue123&error_description=Provider+failure"
            + "#refresh_token=verifier&provider_token=tokenvalue123&sb="
        ))
        let summary = AuthService.googleCallbackShapeSummary(
            hostile,
            expectedState: "expected-state-secret",
            callbackScheme: callbackScheme
        )
        for secret in secrets {
            XCTAssertFalse(summary.contains(secret), "Summary leaked \(secret): \(summary)")
        }
        XCTAssertTrue(summary.contains("state_match=true"), summary)
        XCTAssertTrue(summary.contains("query_unknown=2"), summary)
        XCTAssertTrue(summary.contains("fragment_unknown=2"), summary)
        XCTAssertTrue(summary.contains("query_code=1"), summary)
        XCTAssertTrue(summary.contains("fragment_sb=1"), summary)

        let mismatched = try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?state=other-state-secret&code=c"))
        let mismatchSummary = AuthService.googleCallbackShapeSummary(
            mismatched,
            expectedState: "expected-state-secret",
            callbackScheme: callbackScheme
        )
        XCTAssertTrue(mismatchSummary.contains("state_match=false"), mismatchSummary)
        XCTAssertFalse(mismatchSummary.contains("other-state-secret"), mismatchSummary)
        XCTAssertFalse(mismatchSummary.contains("expected-state-secret"), mismatchSummary)
    }

    // MARK: - Inherited redirect fragments

    /// Fragments that carry any character at all, including punctuation that
    /// parses to zero fields, a second `#` (written literally and encoded),
    /// and encoded control bytes. Every one must fail closed on a success
    /// callback.
    private static let nonEmptyFragments = [
        "&", "=", "?", "/", ".", "-", "0", "_=_", "%20", "%23", "&&", "=&=",
        "#", "##", "%00", "%0A", "%0a%0D", "%09",
        "inherited=1", "sb=", "state=expected", "code=one-time-code",
        "access_token=secret", "error=access_denied&sb=",
    ]

    /// A fragment-less 302 inherits the redirected URL's fragment (RFC 9110
    /// section 10.2.2), so a bare `#` upstream reaches the app as an empty
    /// fragment. Only that exact shape is tolerated beside absence.
    @MainActor
    func testGoogleSuccessCallbackAcceptsOnlyAbsentOrExactlyEmptyFragment() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let base = "\(callbackScheme)://oauth/google?code=one-time-code&state=expected"

        for accepted in [base, base + "#"] {
            let url = try XCTUnwrap(URL(string: accepted))
            XCTAssertEqual(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                "one-time-code",
                accepted
            )
        }

        for fragment in Self.nonEmptyFragments {
            let url = try XCTUnwrap(URL(string: base + "#" + fragment), fragment)
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                fragment
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid, fragment)
            }
        }
    }

    /// Tolerating an empty fragment relaxes nothing else: state, code count,
    /// extra fields, host, path and scheme are all still exact.
    @MainActor
    func testEmptyFragmentDoesNotRelaxAnyOtherGoogleCallbackCheck() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        for invalid in [
            "\(callbackScheme)://oauth/google?code=one-time-code&state=other#",
            "\(callbackScheme)://oauth/google?code=one-time-code#",
            "\(callbackScheme)://oauth/google?state=expected#",
            "\(callbackScheme)://oauth/google?code=one-time-code&state=expected&state=expected#",
            "\(callbackScheme)://oauth/google?code=one-time-code&code=second&state=expected#",
            "\(callbackScheme)://oauth/google?code=one-time-code&state=expected&error_code=unexpected_failure#",
            "\(callbackScheme)://oauth/google?code=one-time-code&state=expected&access_token=secret#",
            "\(callbackScheme)://oauth/google?code=&state=expected#",
            "\(callbackScheme)://other/google?code=one-time-code&state=expected#",
            "\(callbackScheme)://oauth/other?code=one-time-code&state=expected#",
            "\(callbackScheme).evil://oauth/google?code=one-time-code&state=expected#",
        ] {
            let url = try XCTUnwrap(URL(string: invalid), invalid)
            XCTAssertThrowsError(
                try AuthService.validatedGoogleOAuthCode(url, expectedState: "expected", callbackScheme: callbackScheme),
                invalid
            ) { error in
                XCTAssertEqual(error as? UserVisibleError, .oauthCallbackInvalid, invalid)
            }
        }
    }

    /// `fragment_empty` comes from the raw URL text. Zero parsed fragment
    /// fields (as with `#&`) must never be reported as an empty fragment.
    @MainActor
    func testGoogleCallbackShapeSummaryReportsExactFragmentEmptiness() throws {
        let callbackScheme = try XCTUnwrap(AuthService.oauthCallbackScheme)
        let base = "\(callbackScheme)://oauth/google?code=one-time-code-secret&state=expected-state-secret"
        func summary(_ suffix: String) throws -> String {
            AuthService.googleCallbackShapeSummary(
                try XCTUnwrap(URL(string: base + suffix)),
                expectedState: "expected-state-secret",
                callbackScheme: callbackScheme
            )
        }

        let absent = try summary("")
        XCTAssertTrue(absent.contains("fragment_present=false"), absent)
        XCTAssertTrue(absent.contains("fragment_empty=false"), absent)

        let empty = try summary("#")
        XCTAssertTrue(empty.contains("fragment_present=true"), empty)
        XCTAssertTrue(empty.contains("fragment_empty=true"), empty)

        for punctuation in ["#&", "#=", "#?", "#&&", "##", "#%00", "#%0A"] {
            let text = try summary(punctuation)
            XCTAssertTrue(text.contains("fragment_present=true"), text)
            XCTAssertTrue(text.contains("fragment_empty=false"), "\(punctuation): \(text)")
        }

        let inherited = try summary("#inheritedname=inheritedvalue")
        XCTAssertTrue(inherited.contains("fragment_present=true"), inherited)
        XCTAssertTrue(inherited.contains("fragment_empty=false"), inherited)
        XCTAssertTrue(inherited.contains("fragment_unknown=1"), inherited)
        for leaked in ["inheritedname", "inheritedvalue", "one-time-code-secret", "expected-state-secret"] {
            for text in [absent, empty, inherited] {
                XCTAssertFalse(text.contains(leaked), "Summary leaked \(leaked): \(text)")
            }
        }
    }

    /// An empty inherited fragment leads to exactly one PKCE exchange, bound
    /// to this flow's own verifier, and the resulting session is stored.
    @MainActor
    func testGoogleServiceExchangesOncePKCEForEmptyFragmentSuccessCallback() async throws {
        var storedPayload: String?
        nonisolated(unsafe) var requests: [URLRequest] = []
        nonisolated(unsafe) var authorizationURL: URL?
        let auth = AuthService(
            session: makeCountingSession(),
            readSessionPayload: { storedPayload },
            saveSessionPayload: { storedPayload = $0 },
            deleteSessionPayload: { storedPayload = nil },
            webAuthentication: { url, callbackScheme in
                authorizationURL = url
                let state = try Self.state(inAuthorizationURL: url)
                // Supabase emits `code` before the preserved `state`; the
                // trailing `#` is the inherited empty fragment.
                return try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?code=single-use-code&state=\(state)#"))
            }
        )
        defer { AuthReliabilityURLProtocol.handler = nil }
        AuthReliabilityURLProtocol.handler = { request in
            requests.append(request)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"access_token":"google-access","refresh_token":"google-refresh","expires_in":3600,"user":{"id":"google-user","email":"player@example.com"}}"#.utf8)
            )
        }

        let session = try await auth.signInWithGoogle(config: try makeConfig())

        XCTAssertEqual(requests.count, 1)
        let tokenRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.url?.path, "/auth/v1/token")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(tokenRequest.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "grant_type" })?.value,
            "pkce"
        )
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(Self.bodyData(of: tokenRequest))) as? [String: String]
        )
        XCTAssertEqual(body["auth_code"], "single-use-code")
        let verifier = try XCTUnwrap(body["code_verifier"])
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let authorizationQuery = URLComponents(
            url: try XCTUnwrap(authorizationURL),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        XCTAssertEqual(authorizationQuery.first(where: { $0.name == "code_challenge" })?.value, challenge)
        XCTAssertEqual(session.userID, "google-user")
        XCTAssertNotNil(storedPayload)
        XCTAssertEqual(try auth.restoreSessionOrThrow(), session)
    }

    /// A success callback with any non-empty fragment stops before the PKCE
    /// exchange: no request leaves the app and nothing is stored.
    @MainActor
    func testGoogleServiceNonEmptyFragmentSuccessCallbacksMakeZeroRequestsAndWriteNoCredential() async throws {
        for fragment in Self.nonEmptyFragments {
            var storedPayload: String?
            nonisolated(unsafe) var requestCount = 0
            let auth = AuthService(
                session: makeCountingSession(),
                readSessionPayload: { storedPayload },
                saveSessionPayload: { storedPayload = $0 },
                deleteSessionPayload: { storedPayload = nil },
                webAuthentication: { url, callbackScheme in
                    let state = try Self.state(inAuthorizationURL: url)
                    return try XCTUnwrap(URL(string: "\(callbackScheme)://oauth/google?code=must-not-exchange&state=\(state)#\(fragment)"))
                }
            )
            AuthReliabilityURLProtocol.handler = { request in
                requestCount += 1
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"access_token":"must-not-store","refresh_token":"r","expires_in":3600,"user":{"id":"u"}}"#.utf8)
                )
            }
            do {
                _ = try await auth.signInWithGoogle(config: try makeConfig())
                XCTFail("Expected fragment \(fragment) to fail before token exchange")
            } catch let error as UserVisibleError {
                XCTAssertEqual(error, .oauthCallbackInvalid, fragment)
            }
            AuthReliabilityURLProtocol.handler = nil
            XCTAssertEqual(requestCount, 0, fragment)
            XCTAssertNil(storedPayload, fragment)
            XCTAssertNil(try auth.restoreSessionOrThrow(), fragment)
        }
    }

    @MainActor
    func testGoogleCallbackDiagnosticIsOneShotAndDoesNotLeakAcrossAttempts() async throws {
        var storedPayload: String?
        nonisolated(unsafe) var attempt = 0
        let auth = AuthService(
            session: makeCountingSession(),
            readSessionPayload: { storedPayload },
            saveSessionPayload: { storedPayload = $0 },
            deleteSessionPayload: { storedPayload = nil },
            webAuthentication: { _, callbackScheme in
                attempt += 1
                if attempt == 1 {
                    return try XCTUnwrap(URL(string:
                        "\(callbackScheme)://oauth/google?state=other-state-secret&code=callback-code-secret"
                    ))
                }
                throw UserVisibleError.networkUnavailable
            }
        )

        do {
            _ = try await auth.signInWithGoogle(config: try makeConfig())
            XCTFail("Expected the mismatched callback to fail")
        } catch let error as UserVisibleError {
            XCTAssertEqual(error, .oauthCallbackInvalid)
        }
        let diagnostic = try XCTUnwrap(auth.consumeGoogleCallbackDiagnostic())
        XCTAssertEqual(diagnostic.reference, "GCB-STATE-MISMATCH")
        XCTAssertFalse(diagnostic.userMessage.contains("other-state-secret"))
        XCTAssertFalse(diagnostic.userMessage.contains("callback-code-secret"))
        XCTAssertNil(auth.consumeGoogleCallbackDiagnostic(), "A reference must be consumed exactly once")
        XCTAssertNil(storedPayload)

        do {
            _ = try await auth.signInWithGoogle(config: try makeConfig())
            XCTFail("Expected the unrelated network failure")
        } catch let error as UserVisibleError {
            XCTAssertEqual(error, .networkUnavailable)
        }
        XCTAssertNil(auth.consumeGoogleCallbackDiagnostic(), "A later non-callback failure must not reuse GCB-STATE-MISMATCH")
        XCTAssertNil(storedPayload)
    }

    @MainActor
    func testGoogleCallbackDiagnosticReachesModelNoticeWithoutLeakingCallbackData() async throws {
        var storedPayload: String?
        let auth = AuthService(
            session: makeCountingSession(),
            readSessionPayload: { storedPayload },
            saveSessionPayload: { storedPayload = $0 },
            deleteSessionPayload: { storedPayload = nil },
            webAuthentication: { _, callbackScheme in
                try XCTUnwrap(URL(string:
                    "\(callbackScheme)://oauth/google?state=other-state-secret&code=callback-code-secret"
                ))
            }
        )
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthReliability-GCB-\(UUID().uuidString).json")
        defer {
            AuthReliabilityURLProtocol.handler = nil
            try? FileManager.default.removeItem(at: stateURL)
        }
        AuthReliabilityURLProtocol.handler = { request in
            guard request.url?.path == "/auth/v1/settings" else {
                throw URLError(.badURL)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"external":{"apple":false,"google":true}}"#.utf8)
            )
        }
        let model = AppModel(
            persistenceStore: .ephemeral(fileURL: stateURL),
            authService: auth
        )
        model.config = try makeConfig()
        await model.loadAuthProviderConfiguration()
        XCTAssertTrue(model.googleSignInAvailable)

        await model.completeGoogleSignIn()

        XCTAssertEqual(model.lastError, .oauthCallbackInvalid)
        let notice = try XCTUnwrap(model.authNotice)
        XCTAssertTrue(model.authNoticeIsError)
        XCTAssertTrue(notice.contains("GCB-STATE-MISMATCH"), notice)
        XCTAssertFalse(notice.contains("other-state-secret"), notice)
        XCTAssertFalse(notice.contains("callback-code-secret"), notice)
        XCTAssertNil(auth.consumeGoogleCallbackDiagnostic(), "AppModel must consume the reference after surfacing it")
        XCTAssertNil(storedPayload)
    }

    private func makeCountingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthReliabilityURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeConfig() throws -> AppConfig {
        AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: try XCTUnwrap(URL(string: "https://abcdefghijklmnopqrst.supabase.co")),
            supabasePublishableKey: "sb_publishable_0123456789abcdefghij"
        )
    }

    /// The state the service placed in its own `redirect_to`, so a stubbed
    /// callback can pass the state check and reach the fragment rule.
    private static func state(inAuthorizationURL url: URL) throws -> String {
        let redirect = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "redirect_to" })?.value
        )
        return try XCTUnwrap(
            URLComponents(string: redirect)?.queryItems?.first(where: { $0.name == "state" })?.value
        )
    }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }

    @MainActor
    func testCancelledGoogleFlowDoesNotPersistASession() async throws {
        var storedPayload: String?
        let auth = AuthService(
            readSessionPayload: { storedPayload },
            saveSessionPayload: { storedPayload = $0 },
            deleteSessionPayload: { storedPayload = nil },
            webAuthentication: { _, _ in throw CancellationError() }
        )
        let config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: try XCTUnwrap(URL(string: "https://abcdefghijklmnopqrst.supabase.co")),
            supabasePublishableKey: "sb_publishable_0123456789abcdefghij"
        )

        do {
            _ = try await auth.signInWithGoogle(config: config)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not converted to a failed or persisted sign-in.
        }
        XCTAssertNil(storedPayload)
        XCTAssertNil(try auth.restoreSessionOrThrow())
    }

    @MainActor
    func testAppleRejectsAnEmptyNonceBeforeRequestingAToken() async throws {
        let auth = AuthService()
        let config = AppConfig(
            environment: .staging,
            apiBaseURL: AppConfig.approvedProductionAPIOrigin,
            supabaseURL: try XCTUnwrap(URL(string: "https://abcdefghijklmnopqrst.supabase.co")),
            supabasePublishableKey: "sb_publishable_0123456789abcdefghij"
        )

        do {
            _ = try await auth.signInWithApple(
                identityToken: Data("identity-token".utf8),
                rawNonce: "   ",
                config: config
            )
            XCTFail("Expected an empty nonce to fail before network authentication")
        } catch let error as UserVisibleError {
            XCTAssertEqual(error, .authenticationFailed)
        }
    }
}
