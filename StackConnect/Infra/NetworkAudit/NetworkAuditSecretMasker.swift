import Foundation

/// The single place that decides what is a secret in an audited exchange and
/// how it is masked. Every stored event and every export format goes through
/// it, so "secrets always leave masked" holds in one place.
///
/// Classified as secrets:
/// - headers: `Authorization` / `Proxy-Authorization` (Bearer JWTs of App Store
///   Connect, Google access tokens, Basic), `Cookie` / `Set-Cookie` (Apple ID
///   web session), API key headers and any header whose name carries `token`,
///   `secret`, `session`, `auth` or `api-key`;
/// - URL query parameters: `key=`, `access_token`, `refresh_token`, `id_token`,
///   `client_secret`, `assertion`, `code`, signatures…;
/// - body fields (JSON and form-encoded): `access_token`, `refresh_token`,
///   `id_token`, `assertion`, `client_secret`, `private_key`, `password`…;
/// - free text anywhere in a body: PEM private keys (`.p8` contents), JWTs,
///   Google access / refresh tokens and Google API keys.
enum NetworkAuditSecretMasker {

    /// What replaces a secret in stored events and every export.
    static let mask = "[MASKED]"
    /// What the UI shows after the visible prefix of a masked secret.
    static let previewDots = "••••••••"

    // MARK: - Headers

    private static let secretHeaderNames: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "x-goog-api-key", "api-key", "apikey", "scnt",
        "x-apple-id-session-id", "x-goog-firebase-installations-auth"
    ]

    private static let secretHeaderFragments = ["token", "secret", "session", "auth", "api-key", "apikey", "password"]

    static func isSecretHeader(_ name: String) -> Bool {
        let lower = name.lowercased()
        if secretHeaderNames.contains(lower) { return true }
        return secretHeaderFragments.contains { lower.contains($0) }
    }

    /// The stored form of a header: secrets masked, with a short UI preview.
    static func maskHeader(name: String, value: String) -> NetworkAuditHeader {
        guard isSecretHeader(name) else {
            return NetworkAuditHeader(name: name, value: value)
        }
        let lower = name.lowercased()
        if lower == "cookie" {
            return NetworkAuditHeader(
                name: name,
                value: maskCookiePairs(value, separator: ";"),
                isSecret: true,
                maskedPreview: maskCookiePairs(value, separator: ";", replacement: previewDots)
            )
        }
        if lower == "set-cookie" {
            return NetworkAuditHeader(
                name: name,
                value: maskSetCookie(value, replacement: mask),
                isSecret: true,
                maskedPreview: maskSetCookie(value, replacement: previewDots)
            )
        }
        if let (scheme, credential) = splitScheme(value) {
            return NetworkAuditHeader(
                name: name,
                value: "\(scheme) \(mask)",
                isSecret: true,
                maskedPreview: "\(scheme) \(String(credential.prefix(6)))\(previewDots)"
            )
        }
        return NetworkAuditHeader(name: name, value: mask, isSecret: true, maskedPreview: previewDots)
    }

    /// `Bearer abc` → (`Bearer`, `abc`). `nil` when the value has no auth scheme.
    static func splitScheme(_ value: String) -> (scheme: String, credential: String)? {
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let scheme = String(parts[0])
        let known = ["bearer", "basic", "digest", "token", "key"]
        guard known.contains(scheme.lowercased()) else { return nil }
        return (scheme, String(parts[1]))
    }

    /// `a=1; b=2` → `a=[MASKED]; b=[MASKED]` (cookie names stay visible).
    private static func maskCookiePairs(_ value: String, separator: Character, replacement: String = mask) -> String {
        value.split(separator: separator).map { pair -> String in
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { return trimmed }
            return "\(trimmed[..<equals])=\(replacement)"
        }
        .joined(separator: "\(separator) ")
    }

    /// `id=secret; Path=/; Secure` → `id=[MASKED]; Path=/; Secure`: only the
    /// cookie value is masked, the attributes are not secret.
    private static func maskSetCookie(_ value: String, replacement: String) -> String {
        var parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let equals = first.firstIndex(of: "=") else {
            return replacement
        }
        parts[0] = "\(first[..<equals])=\(replacement)"
        return parts.joined(separator: ";")
    }

    // MARK: - Parameters (query and form bodies)

    private static let secretParameterNames: Set<String> = [
        "key", "apikey", "accesstoken", "refreshtoken", "idtoken", "token",
        "clientsecret", "assertion", "clientassertion", "privatekey", "password",
        "code", "codeverifier", "signature", "xgoogsignature", "sig", "subjecttoken",
        "secret", "sessiontoken", "authtoken"
    ]

    /// Lowercased, without `_` / `-`: `access_token`, `accessToken` and
    /// `X-Goog-Signature` normalize the same way.
    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0 != "_" && $0 != "-" }
    }

    static func isSecretParameter(_ name: String) -> Bool {
        let key = normalized(name)
        if secretParameterNames.contains(key) { return true }
        return key.hasSuffix("token") || key.hasSuffix("secret") || key.hasSuffix("password")
    }

    /// JSON field names that hold secrets. Unlike URL parameters, a bare `key`
    /// or `code` is not masked in JSON: Remote Config parameter keys and error
    /// codes would become unreadable.
    static func isSecretJSONField(_ name: String) -> Bool {
        let key = normalized(name)
        if ["key", "code", "signature", "sig"].contains(key) { return false }
        if isSecretParameter(name) { return true }
        return key == "privatekeypem" || key == "p8"
    }

    /// The SRP values and the two-factor code of an Apple ID sign-in
    /// (`idmsa.apple.com`: `a`, `b`, `c`, `m1`, `m2`, `salt`, `securityCode` /
    /// `code`, `password`). Masked for good in the bodies of the core's
    /// `apple_id.*` operations: never stored, so never revealable.
    static let appleSignInSecretFields: Set<String> = ["a", "b", "c", "m1", "m2", "salt", "securitycode", "code", "password", "trusttoken", "trusttokens"]

    /// `a=1&key=XYZ` → `a=1&key=[MASKED]`. Encoding of the visible parts is kept.
    static func maskQuery(_ query: String, extraSecretFields: Set<String> = []) -> String {
        query.split(separator: "&", omittingEmptySubsequences: false).map { item -> String in
            let pair = String(item)
            guard let equals = pair.firstIndex(of: "=") else { return pair }
            let rawName = String(pair[..<equals])
            let name = rawName.removingPercentEncoding ?? rawName
            let isSecret = isSecretParameter(name) || extraSecretFields.contains(normalized(name))
            return isSecret ? "\(rawName)=\(mask)" : pair
        }
        .joined(separator: "&")
    }

    /// The URL with secret query parameters (and any embedded password) masked.
    /// The result is for display and export, not for loading.
    static func maskURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return maskFreeText(url.absoluteString)
        }
        let query = components.percentEncodedQuery
        components.percentEncodedQuery = nil
        if components.password != nil {
            components.password = "MASKED"
        }
        var string = components.string ?? url.absoluteString
        if let query {
            if let hashIndex = string.firstIndex(of: "#") {
                string.insert(contentsOf: "?" + maskQuery(query), at: hashIndex)
            } else {
                string += "?" + maskQuery(query)
            }
        }
        return string
    }

    /// Path + masked query, for list rows.
    static func maskedPathAndQuery(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else {
            return path
        }
        return "\(path)?\(maskQuery(query))"
    }

    // MARK: - Bodies

    /// A readable, masked rendering of a body, or `nil` when it is binary.
    /// - Parameter extraSecretFields: more field names (normalized: lowercased,
    ///   without `_` / `-`) to mask in JSON and form bodies, e.g.
    ///   `appleSignInSecretFields`.
    static func maskBody(_ data: Data, contentType: String?, extraSecretFields: Set<String> = []) -> String? {
        guard !data.isEmpty else { return "" }
        let type = contentType?.lowercased() ?? ""

        if type.contains("json") || data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "[") {
            if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                let masked = maskJSON(object, extraSecretFields: extraSecretFields)
                if JSONSerialization.isValidJSONObject(masked),
                   let pretty = try? JSONSerialization.data(
                       withJSONObject: masked,
                       options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                   ),
                   let text = String(data: pretty, encoding: .utf8) {
                    return maskFreeText(text)
                }
            }
        }

        guard let text = String(data: data, encoding: .utf8), !looksBinary(text) else {
            return nil
        }
        if type.contains("x-www-form-urlencoded") || looksFormEncoded(text) {
            return maskFreeText(maskQuery(text, extraSecretFields: extraSecretFields))
        }
        return maskFreeText(text)
    }

    /// Replaces the value of every secret field, at any depth.
    static func maskJSON(_ object: Any, extraSecretFields: Set<String> = []) -> Any {
        if let dictionary = object as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                let isSecret = isSecretJSONField(key) || extraSecretFields.contains(normalized(key))
                result[key] = isSecret ? mask : maskJSON(value, extraSecretFields: extraSecretFields)
            }
            return result
        }
        if let array = object as? [Any] {
            return array.map { maskJSON($0, extraSecretFields: extraSecretFields) }
        }
        return object
    }

    private static func looksFormEncoded(_ text: String) -> Bool {
        guard !text.contains(" "), !text.contains("\n"), text.contains("=") else { return false }
        return text.range(of: #"^[A-Za-z0-9_.\-%+]+=[^&]*(&[A-Za-z0-9_.\-%+]+=[^&]*)*$"#, options: .regularExpression) != nil
    }

    private static func looksBinary(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value == 0 }
    }

    // MARK: - Free text

    private static let freeTextPatterns: [String] = [
        // PEM private keys: the content of an imported .p8, service account
        // keys (also with escaped newlines inside JSON strings).
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        // JWTs (App Store Connect tokens, OAuth assertions, ID tokens).
        #"eyJ[A-Za-z0-9_\-]{5,}\.eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*"#,
        // Google OAuth access tokens and refresh tokens.
        #"ya29\.[A-Za-z0-9_\-\.]{10,}"#,
        #"1//[A-Za-z0-9_\-]{20,}"#,
        // Google API keys.
        #"AIza[0-9A-Za-z_\-]{35}"#
    ]

    /// Masks secrets that can show up anywhere in a text, whatever the field.
    static func maskFreeText(_ text: String) -> String {
        var result = text
        for pattern in freeTextPatterns {
            result = result.replacingOccurrences(of: pattern, with: mask, options: .regularExpression)
        }
        return result
    }

    // MARK: - Credentials

    /// Describes the credential of an `Authorization` value, without keeping it.
    /// - Parameter googleTokenExpiry: the expiry of a Google access token, when
    ///   the token response that issued it was seen (`NetworkAuditTokenExpiryRegistry`).
    static func credentialInfo(
        forAuthorization value: String,
        googleTokenExpiry: (String) -> Date? = { _ in nil }
    ) -> NetworkAuditCredentialInfo {
        guard let (scheme, token) = splitScheme(value), scheme.lowercased() == "bearer" else {
            return NetworkAuditCredentialInfo(kind: .other, expiresAt: nil)
        }
        if let claims = jwtClaims(token) {
            let expiry = (claims["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let audiences: [String]
            if let single = claims["aud"] as? String {
                audiences = [single]
            } else {
                audiences = claims["aud"] as? [String] ?? []
            }
            let kind: NetworkAuditCredentialInfo.Kind = audiences.contains("appstoreconnect-v1") ? .appStoreConnectJWT : .other
            return NetworkAuditCredentialInfo(kind: kind, expiresAt: expiry)
        }
        if token.hasPrefix("ya29.") {
            return NetworkAuditCredentialInfo(kind: .googleAccessToken, expiresAt: googleTokenExpiry(token))
        }
        return NetworkAuditCredentialInfo(kind: .other, expiresAt: nil)
    }

    /// The payload of a JWT, or `nil` when `token` isn't one.
    static func jwtClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Token inclusion policy

/// Whether a cURL export may carry the real token of an event.
///
/// Only short-lived tokens qualify (App Store Connect JWT, Google access
/// token), and only while still valid. Apple ID session cookies,
/// `refresh_token`, OAuth assertions and private keys are always masked: they
/// are not in `Authorization`, and they are never stored unmasked anyway.
enum NetworkAuditTokenInclusion: Equatable, Sendable {
    /// The request carried no `Authorization` header.
    case notApplicable
    /// A long-lived or unknown credential: never leaves masked.
    case alwaysMasked
    /// A short-lived token whose expiry isn't known: can't be included.
    case unknownValidity(NetworkAuditCredentialInfo.Kind)
    case expired(NetworkAuditCredentialInfo.Kind, at: Date)
    case available(NetworkAuditCredentialInfo.Kind, until: Date)

    var canInclude: Bool {
        if case .available = self { return true }
        return false
    }

    static func evaluate(_ event: NetworkAuditEvent, now: Date) -> NetworkAuditTokenInclusion {
        guard event.requestHeaders.contains(where: { $0.name.caseInsensitiveCompare("Authorization") == .orderedSame }) else {
            return .notApplicable
        }
        guard let credential = event.credential, credential.isShortLived else {
            return .alwaysMasked
        }
        guard let expiry = credential.expiresAt else {
            return .unknownValidity(credential.kind)
        }
        return expiry > now ? .available(credential.kind, until: expiry) : .expired(credential.kind, at: expiry)
    }
}
